import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';

import '../../data/models/mokuro_models.dart';

/// Result from the OCR server for a single page.
class OcrPageResult {
  final int imgWidth;
  final int imgHeight;
  final List<MokuroTextBlock> blocks;

  const OcrPageResult({
    required this.imgWidth,
    required this.imgHeight,
    required this.blocks,
  });
}

/// Exception thrown when the OCR server returns an error.
class OcrServerException implements Exception {
  final int statusCode;
  final String message;

  const OcrServerException(this.statusCode, this.message);

  @override
  String toString() => 'OcrServerException($statusCode): $message';
}

/// HTTP client for the Mekuru OCR server.
///
/// Sends manga page images to the server and receives OCR text blocks
/// in mokuro-compatible format. Includes retry logic with exponential
/// backoff for transient failures.
class MangaOcrClient {
  final String serverUrl;
  final String Function() getAuthToken;
  final http.Client _httpClient;
  final Duration _baseRetryDelay;

  static const _maxRetries = 3;
  static const _timeoutDuration = Duration(seconds: 30);

  MangaOcrClient({
    required this.serverUrl,
    required this.getAuthToken,
    http.Client? httpClient,
    Duration baseRetryDelay = const Duration(seconds: 2),
  })  : _httpClient = httpClient ?? http.Client(),
        _baseRetryDelay = baseRetryDelay;

  /// Process a single manga page image through the OCR server.
  ///
  /// Retries up to 3 times with exponential backoff (2s, 4s, 8s).
  /// Throws [OcrServerException] for non-retryable errors (401, 422).
  /// Returns [OcrPageResult] with parsed text blocks on success.
  Future<OcrPageResult> processPage(
    Uint8List imageBytes,
    String filename,
  ) async {
    OcrServerException? lastError;

    for (var attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        return await _sendRequest(imageBytes, filename);
      } on OcrServerException catch (e) {
        // Don't retry auth errors or validation errors
        if (e.statusCode == 401 || e.statusCode == 422) {
          rethrow;
        }

        // For 429 (rate limited), respect Retry-After header if available
        if (e.statusCode == 429) {
          lastError = e;
          // Parse retry delay from message or use exponential backoff
          final delay = _baseRetryDelay * (1 << attempt);
          await Future<void>.delayed(delay);
          continue;
        }

        // For 500 or other errors, retry with backoff
        lastError = e;
        if (attempt < _maxRetries - 1) {
          final delay = _baseRetryDelay * (1 << attempt);
          await Future<void>.delayed(delay);
        }
      } on TimeoutException {
        lastError = const OcrServerException(
          0,
          'Request timed out. The server may be starting up.',
        );
        if (attempt < _maxRetries - 1) {
          final delay = _baseRetryDelay * (1 << attempt);
          await Future<void>.delayed(delay);
        }
      } on Exception catch (e) {
        lastError = OcrServerException(0, 'Network error: $e');
        if (attempt < _maxRetries - 1) {
          final delay = _baseRetryDelay * (1 << attempt);
          await Future<void>.delayed(delay);
        }
      }
    }

    throw lastError ??
        const OcrServerException(0, 'Failed after maximum retries.');
  }

  Future<OcrPageResult> _sendRequest(
    Uint8List imageBytes,
    String filename,
  ) async {
    final contentType = _detectImageContentType(filename, imageBytes);
    final uri = Uri.parse('$serverUrl/ocr');
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer ${getAuthToken()}'
      ..files.add(http.MultipartFile.fromBytes(
        'image',
        imageBytes,
        filename: filename,
        contentType: contentType,
      ));

    final streamedResponse = await _httpClient.send(request).timeout(
          _timeoutDuration,
        );
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      String detail;
      try {
        final body = json.decode(response.body) as Map<String, dynamic>;
        detail = body['detail'] as String? ?? response.body;
      } catch (_) {
        detail = response.body;
      }
      throw OcrServerException(response.statusCode, detail);
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    final blocks = (data['blocks'] as List)
        .map((b) => MokuroTextBlock.fromOcrJson(b as Map<String, dynamic>))
        .toList();

    return OcrPageResult(
      imgWidth: data['img_width'] as int,
      imgHeight: data['img_height'] as int,
      blocks: blocks,
    );
  }

  void dispose() {
    _httpClient.close();
  }

  MediaType _detectImageContentType(String filename, Uint8List bytes) {
    final headerBytes = bytes.length >= 16 ? bytes.sublist(0, 16) : bytes;
    final detected = lookupMimeType(filename, headerBytes: headerBytes);
    if (detected != null && detected.startsWith('image/')) {
      final parts = detected.split('/');
      if (parts.length == 2) {
        return MediaType(parts[0], parts[1]);
      }
    }
    // Default to JPEG when type cannot be inferred.
    return MediaType('image', 'jpeg');
  }
}
