import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mekuru/features/manga/data/services/ocr_failure.dart';
import 'package:mekuru/features/settings/data/services/ocr_server_health_client.dart';

void main() {
  group('OcrServerHealthClient', () {
    test('accepts /health status ok responses', () async {
      final client = OcrServerHealthClient(
        httpClient: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.toString(), 'https://ocr.example.com/health');
          return http.Response('{"status":"ok"}', 200);
        }),
      );

      final result = await client.checkHealth('https://ocr.example.com/');

      expect(result.status, 'ok');
    });

    test('rejects invalid server URLs before making a request', () async {
      final client = OcrServerHealthClient(
        httpClient: MockClient((request) async {
          fail('HTTP request should not be made for invalid URLs.');
        }),
      );

      await expectLater(
        () => client.checkHealth('ocr.example.com'),
        throwsA(
          isA<OcrServerHealthException>().having(
            (error) => error.failure,
            'failure',
            OcrFailure.serverUrlInvalid.code(),
          ),
        ),
      );
    });

    test('surfaces error details from non-200 responses', () async {
      final client = OcrServerHealthClient(
        httpClient: MockClient((request) async {
          return http.Response('{"detail":"Service warming up"}', 503);
        }),
      );

      await expectLater(
        () => client.checkHealth('https://ocr.example.com'),
        throwsA(
          isA<OcrServerHealthException>()
              .having((error) => error.statusCode, 'statusCode', 503)
              .having(
                (error) => error.failure,
                'failure',
                OcrFailure.status.code('503:Service warming up'),
              ),
        ),
      );
    });

    test('rejects unexpected health payloads', () async {
      final client = OcrServerHealthClient(
        httpClient: MockClient((request) async {
          return http.Response('{"status":"warming"}', 200);
        }),
      );

      await expectLater(
        () => client.checkHealth('https://ocr.example.com'),
        throwsA(
          isA<OcrServerHealthException>().having(
            (error) => error.failure,
            'failure',
            OcrFailure.unhealthy.code('warming'),
          ),
        ),
      );
    });
  });
}
