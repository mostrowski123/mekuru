import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/sync/data/services/server_download_work.dart';
import 'package:path/path.dart' as p;

import '../../shared/self_signed_cert.dart';

void main() {
  late HttpServer server;
  late Directory tempDir;
  final original = List<int>.generate(200 * 1024 + 3, (i) => i % 253);
  // What /file serves; a test swaps it (and etag) to "replace" the file.
  var payload = original;
  final rangesSeen = <String?>[];
  final ifRangesSeen = <String?>[];
  // The ETag /file and /cut serve; a test changes it to "replace" the file.
  var etag = '"v1"';

  /// /file honours Range, /norange ignores it, /badrange answers a range
  /// that doesn't match the request, /missing is a 404, /busy a 503.
  Future<void> handle(HttpRequest request) async {
    final response = request.response;
    var range = request.headers.value(HttpHeaders.rangeHeader);
    final ifRange = request.headers.value('if-range');
    rangesSeen.add(range);
    ifRangesSeen.add(ifRange);
    response.headers.set(HttpHeaders.etagHeader, etag);
    // If-Range that doesn't match the current file: send it whole.
    if (ifRange != null && ifRange != etag) range = null;
    switch (request.uri.path) {
      case '/cut':
        // Headers for the whole file, half the body, then a dead socket.
        response.contentLength = payload.length;
        final socket = await response.detachSocket();
        socket.add(payload.sublist(0, payload.length ~/ 2));
        await socket.flush();
        socket.destroy();
        return;
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
    ifRangesSeen.clear();
    etag = '"v1"';
    payload = original;
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

    test(
      'a cut download resumes with If-Range while the file is unchanged',
      () async {
        final client = HttpClient();
        addTearDown(client.close);
        await expectLater(
          downloadResumable(url('/cut'), partPath(), client: client),
          throwsA(isA<IOException>()),
        );
        final kept = File(partPath()).lengthSync();
        expect(kept, greaterThan(0));
        expect(File('${partPath()}.validator').readAsStringSync(), '"v1"');

        await downloadResumable(url('/file'), partPath(), client: client);

        expect(File(partPath()).readAsBytesSync(), payload);
        expect(rangesSeen.last, 'bytes=$kept-');
        expect(ifRangesSeen.last, '"v1"');
        expect(File('${partPath()}.validator').existsSync(), isFalse);
      },
    );

    test(
      'a cut download starts over when the file changed meanwhile',
      () async {
        final client = HttpClient();
        addTearDown(client.close);
        await expectLater(
          downloadResumable(url('/cut'), partPath(), client: client),
          throwsA(isA<IOException>()),
        );
        // e.g. Kavita rebuilt the chapter's zip: other bytes, other ETag.
        etag = '"v2"';
        payload = original.reversed.toList();

        await downloadResumable(url('/file'), partPath(), client: client);

        // The whole new file, not old bytes with the new file's tail.
        expect(File(partPath()).readAsBytesSync(), payload);
        expect(ifRangesSeen.last, '"v1"');
      },
    );

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
      dir = ServerDownloadWorkDir(p.join(tempDir.path, 'job_1'));
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

  test('deleteServerDownloadJobDirs removes only download folders', () async {
    Directory(p.join(tempDir.path, 'job_1')).createSync();
    Directory(p.join(tempDir.path, 'other')).createSync();
    await deleteServerDownloadJobDirs(tempDir.path);
    expect(tempDir.listSync().map((e) => p.basename(e.path)).toSet(), {
      'other',
    });
  });

  test('a rejected certificate fails at once, flagged for the hint', () async {
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
    final dir = ServerDownloadWorkDir(p.join(tempDir.path, 'job_9'));
    await Directory(dir.path).create();

    final over = await runServerDownloadWork(
      serverDownloadWorkInput(
        dir: dir.path,
        fileName: 'book.cbz',
        url: '$base/file',
        headers: const {},
        baseUrl: base,
        allowSelfSigned: false,
      ),
    );

    expect(over, isTrue);
    final status = await dir.readStatus();
    expect(status!.state, ServerDownloadWorkState.failed);
    expect(status.error, serverDownloadUntrustedCertificateError);
  });

  test('InAppServerDownloads.cancel stops one download and marks it', () {
    final client = HttpClient();
    InAppServerDownloads.start('b1', client);
    InAppServerDownloads.cancel('b1');
    expect(InAppServerDownloads.wasCancelled('b1'), isTrue);
    // A closed client refuses new requests.
    expect(
      () => client.getUrl(Uri.parse('http://127.0.0.1/')),
      throwsStateError,
    );
    // Starting the key again clears the mark; cancelling nothing is a no-op.
    InAppServerDownloads.start('b1', HttpClient());
    expect(InAppServerDownloads.wasCancelled('b1'), isFalse);
    InAppServerDownloads.finish('b1');
    InAppServerDownloads.cancel('b1');
    expect(InAppServerDownloads.wasCancelled('b1'), isFalse);
  });
}
