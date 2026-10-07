import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/core/services/download_to_file.dart';
import 'package:path/path.dart' as p;

import '../shared/fake_download_notifiers.dart';

/// [whileOnWifi] around real downloads from a loopback server, with the
/// network check mocked.
void main() {
  // The binding answers the mocked network check, but it also makes every
  // HttpClient return 400; these downloads need the real one.
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  final payload = List<int>.filled(1000, 7);
  late Directory tempDir;
  late HttpServer server;
  late Completer<void> stalled;
  late Completer<void> resume;
  var requests = 0;

  Future<void> download(String path) {
    final client = HttpClient();
    return whileOnWifi(
      client,
      () => downloadToFile(
        'http://127.0.0.1:${server.port}$path',
        p.join(tempDir.path, 'file'),
        client: client,
      ),
      every: const Duration(milliseconds: 10),
    );
  }

  setUp(() async {
    mockWifiConnected(true);
    tempDir = Directory.systemTemp.createTempSync('network_status_test_');
    stalled = Completer<void>();
    resume = Completer<void>();
    requests = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests++;
      final response = request.response;
      switch (request.uri.path) {
        case '/whole':
          response.contentLength = payload.length;
          response.add(payload);
        case '/stall':
          // Half the body, then nothing until the client gives up.
          response.contentLength = payload.length * 2;
          response.add(payload);
          await response.flush();
          stalled.complete();
          return;
        case '/pause':
          // Half the body, then the rest once the test says so.
          response.contentLength = payload.length * 2;
          response.add(payload);
          await response.flush();
          stalled.complete();
          await resume.future;
          response.add(payload);
        default:
          response.statusCode = HttpStatus.notFound;
      }
      await response.close();
    });
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await server.close(force: true);
    tempDir.deleteSync(recursive: true);
  });

  test('a download that stays on Wi-Fi finishes', () async {
    await download('/whole');
    expect(File(p.join(tempDir.path, 'file')).readAsBytesSync(), payload);
  });

  test('losing Wi-Fi stops the download', () async {
    final done = download('/stall');
    await stalled.future;
    mockWifiConnected(false);
    await expectLater(done, throwsA(isA<WifiLostException>()));
  });

  test('off Wi-Fi nothing is requested', () async {
    mockWifiConnected(false);
    await expectLater(download('/whole'), throwsA(isA<WifiLostException>()));
    expect(requests, 0);
  });

  test('other failures on Wi-Fi are reported as they are', () async {
    await expectLater(download('/missing'), throwsA(isA<HttpException>()));
  });

  group('Android in the background', () {
    // Android blocks a backgrounded app's network, and its Wi-Fi check then
    // reads false.
    setUp(
      () => binding.handleAppLifecycleStateChanged(AppLifecycleState.paused),
    );

    test('the blocked Wi-Fi check does not stop the download', () async {
      final done = download('/pause');
      await stalled.future;
      mockWifiConnected(false);
      // Several of the watcher's checks.
      await Future<void>.delayed(const Duration(milliseconds: 60));
      resume.complete();
      await done;
      expect(File(p.join(tempDir.path, 'file')).lengthSync(), 2000);
    });

    test(
      'starting off Wi-Fi there says it stopped in the background',
      () async {
        mockWifiConnected(false);
        await expectLater(
          download('/whole'),
          throwsA(isA<DownloadStoppedInBackgroundException>()),
        );
        expect(requests, 0);
      },
    );

    test('a transfer that fails says it stopped in the background', () async {
      await expectLater(
        download('/missing'),
        throwsA(isA<DownloadStoppedInBackgroundException>()),
      );
    });

    test('iOS still stops when Wi-Fi goes', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final done = download('/stall');
      await stalled.future;
      mockWifiConnected(false);
      await expectLater(done, throwsA(isA<WifiLostException>()));
    });
  });
}
