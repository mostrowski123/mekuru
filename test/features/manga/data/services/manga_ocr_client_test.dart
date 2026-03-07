import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mekuru/features/manga/data/services/manga_ocr_client.dart';

void main() {
  const serverUrl = 'https://test-ocr.example.com';
  const testToken = 'test-firebase-token';
  const jsonHeaders = {'content-type': 'application/json; charset=utf-8'};

  final successResponse = json.encode({
    'img_width': 1700,
    'img_height': 2400,
    'blocks': [
      {
        'box': [100.0, 200.0, 500.0, 800.0],
        'vertical': true,
        'font_size': 36.5,
        'lines_coords': [
          [
            [100, 200],
            [500, 200],
            [500, 800],
            [100, 800],
          ],
        ],
        'lines': ['テスト'],
      },
    ],
  });

  final emptyBlocksResponse = json.encode({
    'img_width': 800,
    'img_height': 1200,
    'blocks': <Map<String, dynamic>>[],
  });

  final imageBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]);

  /// Creates a client with zero retry delay for fast tests.
  MangaOcrClient createClient(http.Client httpClient) {
    return MangaOcrClient(
      serverUrl: serverUrl,
      getBearerToken: () => testToken,
      httpClient: httpClient,
      baseRetryDelay: Duration.zero,
    );
  }

  group('MangaOcrClient', () {
    test('successful response parses blocks correctly', () async {
      final mockClient = MockClient.streaming((request, _) async {
        expect(request.url.toString(), '$serverUrl/ocr');
        expect(request.method, 'POST');
        expect(request.headers['Authorization'], 'Bearer $testToken');

        return http.StreamedResponse(
          Stream.value(utf8.encode(successResponse)),
          200,
          headers: jsonHeaders,
        );
      });

      final client = createClient(mockClient);

      final result = await client.processPage(imageBytes, 'page_001.jpg');

      expect(result.imgWidth, 1700);
      expect(result.imgHeight, 2400);
      expect(result.blocks, hasLength(1));
      expect(result.blocks[0].lines, ['テスト']);
      expect(result.blocks[0].vertical, isTrue);
      expect(result.blocks[0].fontSize, 36.5);

      client.dispose();
    });

    test('empty blocks response returns empty list', () async {
      final mockClient = MockClient.streaming((request, _) async {
        return http.StreamedResponse(
          Stream.value(utf8.encode(emptyBlocksResponse)),
          200,
          headers: jsonHeaders,
        );
      });

      final client = createClient(mockClient);

      final result = await client.processPage(imageBytes, 'page_001.jpg');

      expect(result.blocks, isEmpty);
      expect(result.imgWidth, 800);

      client.dispose();
    });

    test('401 throws immediately without retry', () async {
      var callCount = 0;
      final mockClient = MockClient.streaming((request, _) async {
        callCount++;
        return http.StreamedResponse(
          Stream.value(utf8.encode('{"detail":"Invalid token"}')),
          401,
          headers: jsonHeaders,
        );
      });

      final client = createClient(mockClient);

      await expectLater(
        () => client.processPage(imageBytes, 'page_001.jpg'),
        throwsA(
          isA<OcrServerException>().having(
            (e) => e.statusCode,
            'statusCode',
            401,
          ),
        ),
      );

      // 401 should not retry — exactly 1 call
      expect(callCount, 1);

      client.dispose();
    });

    test('422 throws immediately without retry', () async {
      var callCount = 0;
      final mockClient = MockClient.streaming((request, _) async {
        callCount++;
        return http.StreamedResponse(
          Stream.value(utf8.encode('{"detail":"Invalid image format"}')),
          422,
          headers: jsonHeaders,
        );
      });

      final client = createClient(mockClient);

      await expectLater(
        () => client.processPage(imageBytes, 'page_001.jpg'),
        throwsA(
          isA<OcrServerException>()
              .having((e) => e.statusCode, 'statusCode', 422)
              .having((e) => e.message, 'message', 'Invalid image format'),
        ),
      );

      expect(callCount, 1);

      client.dispose();
    });

    test('500 retries and succeeds on second attempt', () async {
      var callCount = 0;
      final mockClient = MockClient.streaming((request, _) async {
        callCount++;
        if (callCount == 1) {
          return http.StreamedResponse(
            Stream.value(utf8.encode('{"detail":"Internal error"}')),
            500,
            headers: jsonHeaders,
          );
        }
        return http.StreamedResponse(
          Stream.value(utf8.encode(successResponse)),
          200,
          headers: jsonHeaders,
        );
      });

      final client = createClient(mockClient);

      final result = await client.processPage(imageBytes, 'page_001.jpg');

      expect(result.imgWidth, 1700);
      expect(callCount, 2);

      client.dispose();
    });

    test('500 exhausts retries and throws', () async {
      var callCount = 0;
      final mockClient = MockClient.streaming((request, _) async {
        callCount++;
        return http.StreamedResponse(
          Stream.value(utf8.encode('{"detail":"Server error"}')),
          500,
          headers: jsonHeaders,
        );
      });

      final client = createClient(mockClient);

      await expectLater(
        () => client.processPage(imageBytes, 'page_001.jpg'),
        throwsA(
          isA<OcrServerException>().having(
            (e) => e.statusCode,
            'statusCode',
            500,
          ),
        ),
      );

      // Should have tried 3 times (initial + 2 retries)
      expect(callCount, 3);

      client.dispose();
    });

    test('multipart request includes image file', () async {
      http.BaseRequest? capturedRequest;
      final mockClient = MockClient.streaming((request, _) async {
        capturedRequest = request;
        return http.StreamedResponse(
          Stream.value(utf8.encode(emptyBlocksResponse)),
          200,
          headers: jsonHeaders,
        );
      });

      final client = createClient(mockClient);

      await client.processPage(imageBytes, 'test_page.png');

      expect(capturedRequest, isA<http.MultipartRequest>());
      final multipart = capturedRequest as http.MultipartRequest;
      expect(multipart.files, hasLength(1));
      expect(multipart.files[0].field, 'image');
      expect(multipart.files[0].filename, 'test_page.png');
      expect(multipart.fields, isEmpty);

      client.dispose();
    });

    test('job metadata is attached when provided', () async {
      http.BaseRequest? capturedRequest;
      final mockClient = MockClient.streaming((request, _) async {
        capturedRequest = request;
        return http.StreamedResponse(
          Stream.value(utf8.encode(emptyBlocksResponse)),
          200,
          headers: jsonHeaders,
        );
      });

      final client = createClient(mockClient);

      await client.processPage(
        imageBytes,
        'test_page.png',
        jobId: 'job-123',
        pageIndex: 9,
      );

      final multipart = capturedRequest as http.MultipartRequest;
      expect(multipart.fields['job_id'], 'job-123');
      expect(multipart.fields['page_index'], '9');

      client.dispose();
    });

    test('mismatched job metadata throws before the request is sent', () async {
      var callCount = 0;
      final mockClient = MockClient.streaming((request, _) async {
        callCount++;
        return http.StreamedResponse(
          Stream.value(utf8.encode(emptyBlocksResponse)),
          200,
          headers: jsonHeaders,
        );
      });

      final client = createClient(mockClient);

      await expectLater(
        () => client.processPage(imageBytes, 'page_001.jpg', jobId: 'job-123'),
        throwsA(
          isA<OcrServerException>().having(
            (e) => e.message,
            'message',
            contains('jobId and pageIndex'),
          ),
        ),
      );
      expect(callCount, 0);

      client.dispose();
    });

    test('missing server URL throws before the request is sent', () async {
      var callCount = 0;
      final mockClient = MockClient.streaming((request, _) async {
        callCount++;
        return http.StreamedResponse(
          Stream.value(utf8.encode(emptyBlocksResponse)),
          200,
          headers: jsonHeaders,
        );
      });

      final client = MangaOcrClient(
        serverUrl: '   ',
        getBearerToken: () => testToken,
        httpClient: mockClient,
      );

      await expectLater(
        () => client.processPage(imageBytes, 'page_001.jpg'),
        throwsA(
          isA<OcrServerException>().having(
            (e) => e.message,
            'message',
            'OCR server URL is not configured.',
          ),
        ),
      );

      expect(callCount, 0);
      client.dispose();
    });

    test('invalid server URL throws before the request is sent', () async {
      var callCount = 0;
      final mockClient = MockClient.streaming((request, _) async {
        callCount++;
        return http.StreamedResponse(
          Stream.value(utf8.encode(emptyBlocksResponse)),
          200,
          headers: jsonHeaders,
        );
      });

      final client = MangaOcrClient(
        serverUrl: 'not-a-valid-url',
        getBearerToken: () => testToken,
        httpClient: mockClient,
      );

      await expectLater(
        () => client.processPage(imageBytes, 'page_001.jpg'),
        throwsA(
          isA<OcrServerException>().having(
            (e) => e.message,
            'message',
            'OCR server URL is invalid. Use a full http:// or https:// URL.',
          ),
        ),
      );

      expect(callCount, 0);
      client.dispose();
    });

    test('OcrServerException has correct toString', () {
      const error = OcrServerException(429, 'Rate limited');
      expect(error.toString(), 'OcrServerException(429): Rate limited');
    });

    test('OcrPageResult stores values correctly', () {
      const result = OcrPageResult(imgWidth: 100, imgHeight: 200, blocks: []);
      expect(result.imgWidth, 100);
      expect(result.imgHeight, 200);
      expect(result.blocks, isEmpty);
    });
  });
}
