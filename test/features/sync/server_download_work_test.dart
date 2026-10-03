import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/sync/data/services/server_download_work.dart';
import 'package:path/path.dart' as p;

import '../../shared/self_signed_cert.dart';

void main() {
  late HttpServer server;
  late Directory tempDir;
  final payload = List<int>.generate(200 * 1024 + 3, (i) => i % 253);
  final rangesSeen = <String?>[];

  /// /file honours Range, /norange ignores it, /badrange answers a range
  /// that doesn't match the request, /missing is a 404, /busy a 503.
  Future<void> handle(HttpRequest request) async {
    final response = request.response;
    final range = request.headers.value(HttpHeaders.rangeHeader);
    rangesSeen.add(range);
    switch (request.uri.path) {
      case '/file' when range != null:
        final start = int.parse(range.substring(6, range.length - 1));
        response.statusCode = HttpStatus.partialContent;
        response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-${payload.length - 1}/${payload.length}',
        );
        response.contentLength = payload.length - start;
        response.add(payload.sublist(start));
      case '/badrange' when range != null:
        response.statusCode = HttpStatus.partialContent;
        response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes 0-${payload.length - 1}/${payload.length}',
        );
        response.contentLength = payload.length;
        response.add(payload);
      case '/file' || '/norange' || '/badrange':
        response.contentLength = payload.length;
        response.add(payload);
      case '/busy':
        response.statusCode = HttpStatus.serviceUnavailable;
      default:
        response.statusCode = HttpStatus.notFound;
    }
    await response.close();
  }

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('server_download_work_');
    rangesSeen.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(handle);
  });

  tearDown(() async {
    await server.close(force: true);
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  String url(String path) => 'http://127.0.0.1:${server.port}$path';
  String partPath() => p.join(tempDir.path, 'book.cbz.part');

  group('downloadResumable', () {
    test('downloads a whole file and reports progress', () async {
      final client = HttpClient();
      addTearDown(client.close);
      var lastTotal = 0;
      await downloadResumable(
        url('/file'),
        partPath(),
        client: client,
        onProgress: (received, total) => lastTotal = total,
      );
      expect(File(partPath()).readAsBytesSync(), payload);
      expect(lastTotal, payload.length);
      expect(rangesSeen, [null]);
    });

    test('continues a partial file with a Range request', () async {
      File(partPath()).writeAsBytesSync(payload.sublist(0, 5000));
      final client = HttpClient();
      addTearDown(client.close);
      await downloadResumable(url('/file'), partPath(), client: client);
      expect(File(partPath()).readAsBytesSync(), payload);
      expect(rangesSeen, ['bytes=5000-']);
    });

    test('starts over when the server ignores the range', () async {
      File(partPath()).writeAsBytesSync(List.filled(5000, 7));
      final client = HttpClient();
      addTearDown(client.close);
      await downloadResumable(url('/norange'), partPath(), client: client);
      expect(File(partPath()).readAsBytesSync(), payload);
    });

    test('starts over when the server answers another range', () async {
      File(partPath()).writeAsBytesSync(payload.sublist(0, 5000));
      final client = HttpClient();
      addTearDown(client.close);
      await downloadResumable(url('/badrange'), partPath(), client: client);
      expect(File(partPath()).readAsBytesSync(), payload);
      expect(rangesSeen, ['bytes=5000-', null]);
    });

    test('a 404 is a permanent failure, a 503 is not', () async {
      final client = HttpClient();
      addTearDown(client.close);
      await expectLater(
        downloadResumable(url('/missing'), partPath(), client: client),
        throwsA(
          isA<ServerDownloadHttpException>().having(
            (e) => e.isPermanent,
            'isPermanent',
            isTrue,
          ),
        ),
      );
      await expectLater(
        downloadResumable(url('/busy'), partPath(), client: client),
        throwsA(
          isA<ServerDownloadHttpException>().having(
            (e) => e.isPermanent,
            'isPermanent',
            isFalse,
          ),
        ),
      );
    });
  });

  group('runServerDownloadWork', () {
    late ServerDownloadWorkDir dir;

    Map<String, dynamic> input(String downloadUrl, {String? baseUrl}) =>
        serverDownloadWorkInput(
          dir: dir.path,
          fileName: 'book.cbz',
          url: downloadUrl,
          headers: {'X-API-Key': 'k'},
          baseUrl: baseUrl ?? url(''),
          allowSelfSigned: baseUrl != null,
        );

    setUp(() async {
      dir = ServerDownloadWorkDir(p.join(tempDir.path, 'worker_1'));
      await Directory(dir.path).create();
      await dir.writeJob(key: 'b1', fileName: 'book.cbz', meta: {'x': 1});
    });

    test('finishes: the file is in place and the status says done', () async {
      expect(await runServerDownloadWork(input(url('/file'))), isTrue);
      expect(File(dir.filePath('book.cbz')).readAsBytesSync(), payload);
      expect(File('${dir.filePath('book.cbz')}.part').existsSync(), isFalse);
      final status = await dir.readStatus();
      expect(status!.state, ServerDownloadWorkState.done);
      expect(status.received, payload.length);
      final job = await dir.readJob();
      expect(job!.key, 'b1');
      expect(job.meta, {'x': 1});
    });

    test('gives up at once on a permanent HTTP error', () async {
      expect(await runServerDownloadWork(input(url('/missing'))), isTrue);
      final status = await dir.readStatus();
      expect(status!.state, ServerDownloadWorkState.failed);
      expect(status.error, contains('404'));
    });

    test('retries an unreachable server, then gives up', () async {
      final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final deadUrl = 'http://127.0.0.1:${closed.port}/file';
      await closed.close();

      for (var i = 1; i < serverDownloadMaxFailedAttempts; i++) {
        expect(await runServerDownloadWork(input(deadUrl)), isFalse);
        final status = await dir.readStatus();
        expect(status!.state, ServerDownloadWorkState.running);
        expect(status.failedAttempts, i);
      }
      expect(await runServerDownloadWork(input(deadUrl)), isTrue);
      expect((await dir.readStatus())!.state, ServerDownloadWorkState.failed);
    });

    test('ends quietly when its folder was deleted (cancelled)', () async {
      await Directory(dir.path).delete(recursive: true);
      expect(await runServerDownloadWork(input(url('/file'))), isTrue);
      expect(Directory(dir.path).existsSync(), isFalse);
    });

    test('accepts the self-signed certificate it was told to', () async {
      final secure = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        SecurityContext()
          ..useCertificateChainBytes(utf8.encode(selfSignedCertPem))
          ..usePrivateKeyBytes(utf8.encode(selfSignedKeyPem)),
      );
      addTearDown(() => secure.close(force: true));
      secure.listen(handle);
      final base = 'https://127.0.0.1:${secure.port}';

      expect(
        await runServerDownloadWork(input('$base/file', baseUrl: base)),
        isTrue,
      );
      expect(File(dir.filePath('book.cbz')).readAsBytesSync(), payload);
    });
  });

  test('deleteServerDownloadWorkDirs removes only worker folders', () async {
    Directory(p.join(tempDir.path, 'worker_1')).createSync();
    Directory(p.join(tempDir.path, 'in_app_2')).createSync();
    Directory(p.join(tempDir.path, '1791012234800173')).createSync();
    await deleteServerDownloadWorkDirs(tempDir.path);
    expect(tempDir.listSync().map((e) => p.basename(e.path)).toSet(), {
      'in_app_2',
      '1791012234800173',
    });
  });
}
