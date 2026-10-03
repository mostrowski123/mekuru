import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/services/download_to_file.dart';
import 'package:mekuru/core/services/server_http_client.dart';
import 'package:path/path.dart' as p;

import '../shared/self_signed_cert.dart';

void main() {
  group('acceptsUntrustedCertificate', () {
    test('accepts only the configured https host and port', () {
      const base = 'https://nas.example.com:8443';
      expect(acceptsUntrustedCertificate(base, 'nas.example.com', 8443), true);
      expect(acceptsUntrustedCertificate(base, 'NAS.example.com', 8443), true);
      expect(acceptsUntrustedCertificate(base, 'nas.example.com', 443), false);
      expect(
        acceptsUntrustedCertificate(base, 'evil.example.com', 8443),
        false,
      );
    });

    test('uses the https default port when the URL has none', () {
      const base = 'https://192.168.1.20/komga';
      expect(acceptsUntrustedCertificate(base, '192.168.1.20', 443), true);
      expect(acceptsUntrustedCertificate(base, '192.168.1.20', 8443), false);
    });

    test('never accepts for a plain-http or unparsable base URL', () {
      expect(acceptsUntrustedCertificate('http://nas:80', 'nas', 80), false);
      expect(acceptsUntrustedCertificate('::not a url', 'nas', 443), false);
    });
  });

  group('against an HTTPS server with a self-signed certificate', () {
    late HttpServer server;
    late Directory tempDir;
    String? lastApiKey;
    final payload = List<int>.generate(64 * 1024 + 5, (i) => i % 241);

    String base(String host) => 'https://$host:${server.port}';

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('server_http_client_');
      final context = SecurityContext()
        ..useCertificateChainBytes(utf8.encode(selfSignedCertPem))
        ..usePrivateKeyBytes(utf8.encode(selfSignedKeyPem));
      server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        context,
      );
      server.listen((request) async {
        lastApiKey = request.headers.value('X-API-Key');
        if (request.uri.path == '/file') {
          request.response.contentLength = payload.length;
          request.response.add(payload);
        } else {
          request.response.write('ok');
        }
        await request.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
      tempDir.deleteSync(recursive: true);
    });

    test('the default client rejects the certificate', () async {
      final client = serverHttpClient(
        base('127.0.0.1'),
        allowSelfSigned: false,
      );
      addTearDown(client.close);
      await expectLater(
        client.get(Uri.parse('${base('127.0.0.1')}/health')),
        throwsA(isA<Exception>()),
      );
    });

    test('allowSelfSigned accepts it for the configured server', () async {
      final client = serverHttpClient(base('127.0.0.1'), allowSelfSigned: true);
      addTearDown(client.close);
      final response = await client.get(
        Uri.parse('${base('127.0.0.1')}/health'),
      );
      expect(response.statusCode, 200);
      expect(response.body, 'ok');
    });

    test(
      'allowSelfSigned still rejects a host it was not set up for',
      () async {
        // Trust was granted to "localhost"; the request goes to 127.0.0.1.
        final client = serverHttpClient(
          base('localhost'),
          allowSelfSigned: true,
        );
        addTearDown(client.close);
        await expectLater(
          client.get(Uri.parse('${base('127.0.0.1')}/health')),
          throwsA(isA<Exception>()),
        );
      },
    );

    test(
      'downloadToFile streams through a trusting client with headers',
      () async {
        final destination = p.join(tempDir.path, 'book.cbz');
        await downloadToFile(
          '${base('127.0.0.1')}/file',
          destination,
          headers: {'X-API-Key': 'secret'},
          client: serverIoClient(base('127.0.0.1'), allowSelfSigned: true),
        );
        expect(File(destination).readAsBytesSync(), payload);
        expect(lastApiKey, 'secret');
      },
    );
  });
}
