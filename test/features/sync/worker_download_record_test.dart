import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/manga/data/services/model_download.dart'
    show ModelFile;
import 'package:mekuru/features/manga/data/services/model_download_job.dart';
import 'package:mekuru/features/sync/data/services/server_download_work.dart';
import 'package:path/path.dart' as p;

import '../../shared/self_signed_cert.dart';

/// What the two worker downloads write, in which order, and what they ask the
/// server for, byte for byte. A job the released app queued is picked up by
/// whatever worker the update brings, so the records below are the ones
/// 1.74.5's workers leave, captured from runs of its code.
void main() {
  // Odd length, over the server's 8 KB buffer.
  final payload = List<int>.generate(100 * 1024 + 7, (i) => i % 241);
  final n = payload.length;
  final half = n ~/ 2;
  final small = payload.sublist(0, 100);
  // What a run that got all 100 bytes of /small at once writes.
  const smallProgress =
      '{"state":"running","received":100,"total":100,"failedAttempts":0}';
  const smallDone =
      '{"state":"done","received":100,"total":100,"failedAttempts":0}';
  late HttpServer server;
  late Directory dir;
  final seen = <({String? range, String? ifRange, String? key})>[];
  // The next answer promises the rest, sends half the file, then drops.
  var cutNext = false;

  Future<void> handle(HttpRequest request) async {
    final range = request.headers.value(HttpHeaders.rangeHeader);
    seen.add((
      range: range,
      ifRange: request.headers.value('if-range'),
      key: request.headers.value('x-api-key'),
    ));
    final response = request.response;
    response.headers.set(HttpHeaders.etagHeader, '"v1"');
    if (request.uri.path == '/small') {
      // One chunk, so exactly one progress write whatever the load.
      response.contentLength = small.length;
      response.add(small);
      await response.close();
      return;
    }
    final from = range == null
        ? 0
        : int.parse(range.substring('bytes='.length, range.length - 1));
    if (from > 0) {
      response.statusCode = HttpStatus.partialContent;
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $from-${n - 1}/$n',
      );
    }
    response.contentLength = n - from;
    if (cutNext) {
      cutNext = false;
      final socket = await response.detachSocket();
      socket.add(payload.sublist(from, half));
      await socket.flush();
      socket.destroy();
      return;
    }
    response.add(payload.sublist(from));
    await response.close();
  }

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('worker_download_');
    seen.clear();
    cutNext = false;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(handle);
  });

  tearDown(() async {
    await server.close(force: true);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  String url() => 'http://127.0.0.1:${server.port}/file';
  Future<String> deadUrl() async {
    final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = closed.port;
    await closed.close();
    return 'http://127.0.0.1:$port/file';
  }

  void seed(String name, Object contents) {
    final file = File(p.join(dir.path, name));
    contents is String
        ? file.writeAsStringSync(contents)
        : file.writeAsBytesSync(contents as List<int>);
  }

  String status() => File(p.join(dir.path, 'status.json')).readAsStringSync();
  Set<String> files() => dir.listSync().map((e) => p.basename(e.path)).toSet();
  // Progress writes, at least one: how far it got, and nothing else.
  final someProgress = allOf(
    isNotEmpty,
    everyElement(
      matches(
        RegExp(
          '^\\{"state":"running","received":\\d+,"total":$n,'
          '"failedAttempts":0\\}\$',
        ),
      ),
    ),
  );
  final done = '{"state":"done","received":$n,"total":$n,"failedAttempts":0}';

  group('server book job', () {
    Map<String, dynamic> input([String? from]) => serverDownloadWorkInput(
      dir: dir.path,
      fileName: 'book.cbz',
      url: from ?? url(),
      headers: {'X-API-Key': 'k'},
      baseUrl: 'http://127.0.0.1:${server.port}',
      allowSelfSigned: false,
    );
    final cut =
        '{"state":"running","received":$half,"total":$n,"failedAttempts":1,'
        '"error":"server_status:0"}';

    setUp(() {
      // As ServerDownloadNotifier.download queues it.
      seed(
        'status.json',
        '{"state":"running","received":0,"total":-1,"failedAttempts":0}',
      );
    });

    test('records its progress, then done', () async {
      final (over, writes) = await _recording(
        () => runServerDownloadWork(input()),
      );
      expect(over, isTrue);
      expect(writes.last, done);
      expect(writes.sublist(0, writes.length - 1), someProgress);
      expect(status(), done);
      expect(seen, [(range: null, ifRange: null, key: 'k')]);
      expect(File(p.join(dir.path, 'book.cbz')).readAsBytesSync(), payload);
      expect(files(), {'status.json', 'book.cbz'});
    });

    test('writes no "all there, being checked" status', () async {
      final (over, writes) = await _recording(
        () => runServerDownloadWork(
          input('http://127.0.0.1:${server.port}/small'),
        ),
      );
      expect(over, isTrue);
      expect(writes, [smallProgress, smallDone]);
    });

    test('a cut leaves this record, and the bytes it got', () async {
      // Bytes gained start the count of failed attempts again.
      seed(
        'status.json',
        '{"state":"running","received":0,"total":-1,"failedAttempts":3}',
      );
      cutNext = true;
      final (over, writes) = await _recording(
        () => runServerDownloadWork(input()),
      );
      expect(over, isFalse);
      expect(writes.last, cut);
      expect(writes.sublist(0, writes.length - 1), someProgress);
      expect(status(), cut);
      expect(
        File(p.join(dir.path, 'book.cbz.part')).readAsBytesSync(),
        payload.sublist(0, half),
      );
      expect(
        File(p.join(dir.path, 'book.cbz.part.validator')).readAsStringSync(),
        '"v1"',
      );
    });

    test('resumes the record a released worker left', () async {
      seed('status.json', cut);
      seed('book.cbz.part', payload.sublist(0, half));
      seed('book.cbz.part.validator', '"v1"');
      final (over, writes) = await _recording(
        () => runServerDownloadWork(input()),
      );
      expect(over, isTrue);
      expect(seen, [(range: 'bytes=$half-', ifRange: '"v1"', key: 'k')]);
      expect(writes.last, done);
      expect(File(p.join(dir.path, 'book.cbz')).readAsBytesSync(), payload);
      expect(files(), {'status.json', 'book.cbz'});
    });

    test('ends at once when done, but runs again when it failed', () async {
      seed('status.json', done);
      expect(await runServerDownloadWork(input()), isTrue);
      expect(seen, isEmpty);
      // Unlike a model job, which takes a stop as cancelled.
      seed(
        'status.json',
        '{"state":"failed","received":0,"total":-1,"failedAttempts":0,'
            '"error":"stopped"}',
      );
      expect(await runServerDownloadWork(input()), isTrue);
      expect(seen, hasLength(1));
      expect(status(), done);
    });

    test('the fifth failed attempt gives up with this record', () async {
      seed(
        'status.json',
        '{"state":"running","received":0,"total":-1,"failedAttempts":4}',
      );
      final dead = await deadUrl();
      final (over, writes) = await _recording(
        () => runServerDownloadWork(input(dead)),
      );
      expect(over, isTrue);
      expect(writes, [
        '{"state":"failed","received":0,"total":-1,"failedAttempts":5,'
            '"error":"server_status:0"}',
      ]);
    });
  });

  group('model job', () {
    final events = <String>[];
    var notified = 0;
    final checking =
        '{"state":"running","received":$n,"total":$n,"failedAttempts":0}';
    final cut =
        '{"state":"running","received":$half,"total":$n,"failedAttempts":1,'
        '"error":"server_status:0"}';

    Future<bool> run({String? from, String? sha, List<int>? body}) {
      final served = body ?? payload;
      final ModelFile file = (
        name: 'model.bin',
        url: from ?? url(),
        bytes: served.length,
        sha256: sha ?? sha256.convert(served).toString(),
      );
      return runModelDownloadWork(
        {'dir': dir.path},
        file: file,
        failedEvent: 'test.download_failed',
        notifyFailed: () async => notified++,
      );
    }

    setUp(() {
      events.clear();
      notified = 0;
      usageLogSinkOverride = (event, _, {required isWarning}) =>
          events.add(event);
      addTearDown(() => usageLogSinkOverride = null);
      // As ModelDownloadJob.run queues it.
      seed(
        'status.json',
        '{"state":"running","received":0,"total":$n,"failedAttempts":0}',
      );
    });

    test('records progress, the check, then done, and installs', () async {
      final (over, writes) = await _recording(run);
      expect(over, isTrue);
      expect(writes.sublist(writes.length - 2), [checking, done]);
      expect(writes.sublist(0, writes.length - 2), someProgress);
      expect(seen, [(range: null, ifRange: null, key: null)]);
      expect(File(p.join(dir.path, 'model.bin')).readAsBytesSync(), payload);
      expect(File(p.join(dir.path, 'INSTALLED')).readAsStringSync(), 'ok');
      expect(files(), {'status.json', 'model.bin', 'INSTALLED'});
      expect(events, isEmpty);
      expect(notified, 0);
    });

    test('says it is being checked once every byte is in', () async {
      seed(
        'status.json',
        '{"state":"running","received":0,"total":100,"failedAttempts":0}',
      );
      final (over, writes) = await _recording(
        () => run(from: 'http://127.0.0.1:${server.port}/small', body: small),
      );
      expect(over, isTrue);
      expect(writes, [smallProgress, smallProgress, smallDone]);
    });

    test('a cut leaves this record, and the bytes it got', () async {
      seed(
        'status.json',
        '{"state":"running","received":0,"total":$n,"failedAttempts":3}',
      );
      cutNext = true;
      final (over, writes) = await _recording(run);
      expect(over, isFalse);
      expect(writes.last, cut);
      expect(writes.sublist(0, writes.length - 1), someProgress);
      expect(status(), cut);
      expect(
        File(p.join(dir.path, 'model.bin.part')).readAsBytesSync(),
        payload.sublist(0, half),
      );
      expect(
        File(p.join(dir.path, 'model.bin.part.validator')).readAsStringSync(),
        '"v1"',
      );
      expect(events, isEmpty);
      expect(notified, 0);
    });

    test('resumes the record a released worker left', () async {
      seed('status.json', cut);
      seed('model.bin.part', payload.sublist(0, half));
      seed('model.bin.part.validator', '"v1"');
      final (over, writes) = await _recording(run);
      expect(over, isTrue);
      expect(seen, [(range: 'bytes=$half-', ifRange: '"v1"', key: null)]);
      expect(writes.sublist(writes.length - 2), [checking, done]);
      expect(File(p.join(dir.path, 'model.bin')).readAsBytesSync(), payload);
      expect(files(), {'status.json', 'model.bin', 'INSTALLED'});
    });

    test('ends at once when installed or never queued', () async {
      seed('INSTALLED', 'ok');
      expect(await run(), isTrue);
      File(p.join(dir.path, 'INSTALLED')).deleteSync();
      File(p.join(dir.path, 'status.json')).deleteSync();
      expect(await run(), isTrue);
      expect(seen, isEmpty);
      expect(files(), isEmpty);
    });

    test('a file that fails its check goes, and the job gives up', () async {
      final (over, writes) = await _recording(() => run(sha: 'other'));
      expect(over, isTrue);
      expect(writes.sublist(writes.length - 2), [
        checking,
        '{"state":"failed","received":$n,"total":$n,"failedAttempts":0,'
            '"error":"verification"}',
      ]);
      expect(files(), {'status.json'});
      expect(events, ['test.download_failed']);
      expect(notified, 1);
    });

    test('the fifth failed attempt gives up with this record', () async {
      seed(
        'status.json',
        '{"state":"running","received":0,"total":$n,"failedAttempts":4}',
      );
      final dead = await deadUrl();
      final (over, writes) = await _recording(() => run(from: dead));
      expect(over, isTrue);
      expect(writes, [
        '{"state":"failed","received":0,"total":$n,"failedAttempts":5,'
            '"error":"server_status:0"}',
      ]);
      expect(events, ['test.download_failed']);
      expect(notified, 1);
    });

    test("a rejected certificate is retried, unlike a server book's", () async {
      final secure = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        SecurityContext()
          ..useCertificateChainBytes(utf8.encode(selfSignedCertPem))
          ..usePrivateKeyBytes(utf8.encode(selfSignedKeyPem)),
      );
      addTearDown(() => secure.close(force: true));
      secure.listen(handle);
      final (over, writes) = await _recording(
        () => run(from: 'https://127.0.0.1:${secure.port}/file'),
      );
      expect(over, isFalse);
      expect(writes, [
        '{"state":"running","received":0,"total":$n,"failedAttempts":1,'
            '"error":"untrusted_certificate"}',
      ]);
      expect(events, isEmpty);
      expect(notified, 0);
    });
  });
}

/// [body]'s result and every status it wrote, in order, as written.
Future<(T, List<String>)> _recording<T>(Future<T> Function() body) async {
  final writes = <String>[];
  final result = await IOOverrides.runWithIOOverrides(
    body,
    _StatusWrites(writes),
  );
  return (result, writes);
}

/// Hands out a recording file for `status.json.tmp`, which `writeStringAtomic`
/// writes before renaming it over `status.json`.
final class _StatusWrites extends IOOverrides {
  _StatusWrites(this.writes);

  final List<String> writes;

  @override
  File createFile(String path) {
    final file = super.createFile(path);
    return p.basename(path) == 'status.json.tmp'
        ? _RecordedFile(file, writes)
        : file;
  }
}

/// The calls `writeBytesAtomic` makes on its temporary file.
class _RecordedFile implements File {
  _RecordedFile(this._file, this._writes);

  final File _file;
  final List<String> _writes;

  @override
  String get path => _file.path;

  @override
  Future<File> writeAsBytes(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) {
    _writes.add(utf8.decode(bytes));
    return _file.writeAsBytes(bytes, mode: mode, flush: flush);
  }

  @override
  Future<File> rename(String newPath) => _file.rename(newPath);

  @override
  bool existsSync() => _file.existsSync();

  @override
  void deleteSync({bool recursive = false}) =>
      _file.deleteSync(recursive: recursive);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
