import 'dart:async';
import 'dart:io';

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
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  final payload = List<int>.filled(1000, 7);
  late Directory tempDir;
  late HttpServer server;
  late Completer<void> stalled;
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
        default:
          response.statusCode = HttpStatus.notFound;
      }
      await response.close();
    });
  });

  tearDown(() async {
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
}
