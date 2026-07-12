import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import 'package:mekuru/features/settings/data/services/ocr_server_config.dart'
    as ocr_server_config;

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

  /// Machine-readable error code from structured server errors
  /// (e.g. `job_not_found`, `job_expired`), when the server sent one.
  final String? code;

  /// Server-requested retry delay from a 429 Retry-After header.
  final Duration? retryAfter;

  const OcrServerException(
    this.statusCode,
    this.message, {
    this.code,
    this.retryAfter,
  });

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
  final String Function() getBearerToken;
  final http.Client _httpClient;
  final Duration _baseRetryDelay;

  static const _maxRetries = 3;
  static const _timeoutDuration = Duration(seconds: 30);
  static const _maxRetryAfterDelay = Duration(seconds: 30);

  /// Statuses where a retry cannot succeed: auth failures, validation
  /// errors, and billing-job errors (payment required, forbidden,
  /// job not found, job no longer active).
  static const _nonRetriableStatusCodes = {401, 402, 403, 404, 409, 422};

  MangaOcrClient({
    required this.serverUrl,
    required this.getBearerToken,
    http.Client? httpClient,
    Duration baseRetryDelay = const Duration(seconds: 2),
  }) : _httpClient = httpClient ?? http.Client(),
       _baseRetryDelay = baseRetryDelay;

  /// Process a single manga page image through the OCR server.
  ///
  /// Retries up to 3 times with exponential backoff (2s, 4s, 8s).
  /// Throws [OcrServerException] immediately for non-retriable errors
  /// (401, 402, 403, 404, 409, 422).
  /// Returns [OcrPageResult] with parsed text blocks on success.
  Future<OcrPageResult> processPage(
    Uint8List imageBytes,
    String filename, {
    String? jobId,
    int? pageIndex,
  }) async {
    OcrServerException? lastError;

    for (var attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        return await _sendRequest(
          imageBytes,
          filename,
          jobId: jobId,
          pageIndex: pageIndex,
        );
      } on OcrServerException catch (e) {
        // Don't retry errors a retry cannot fix (auth, validation, billing)
        if (_nonRetriableStatusCodes.contains(e.statusCode)) {
          rethrow;
        }

        // For 429 (rate limited), honor the Retry-After header if present
        if (e.statusCode == 429) {
          lastError = e;
          if (attempt < _maxRetries - 1) {
            var delay = e.retryAfter ?? _baseRetryDelay * (1 << attempt);
            if (delay > _maxRetryAfterDelay) {
              delay = _maxRetryAfterDelay;
            }
            await Future<void>.delayed(delay);
          }
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
    String filename, {
    String? jobId,
    int? pageIndex,
  }) async {
    if ((jobId == null) != (pageIndex == null)) {
      throw const OcrServerException(
        0,
        'jobId and pageIndex must be provided together.',
      );
    }

    final normalizedServerUrl = serverUrl.trim();
    final urlError = ocr_server_config.validateOcrServerUrl(
      normalizedServerUrl,
    );
    if (urlError != null) {
      final message = normalizedServerUrl.isEmpty
          ? 'OCR server URL is not configured.'
          : 'OCR server URL is invalid. Use a full http:// or https:// URL.';
      throw OcrServerException(0, message);
    }

    final baseUri = ocr_server_config.tryParseOcrServerUrl(normalizedServerUrl);
    if (baseUri == null) {
      throw const OcrServerException(
        0,
        'OCR server URL is invalid. Use a full http:// or https:// URL.',
      );
    }
    final uri = baseUri.replace(
      path: '${baseUri.path}/ocr'.replaceAll('//', '/'),
    );

    final contentType = _detectImageContentType(filename, imageBytes);
    final request = http.MultipartRequest('POST', uri)
      ..files.add(
        http.MultipartFile.fromBytes(
          'image',
          imageBytes,
          filename: filename,
          contentType: contentType,
        ),
      );
    final bearerToken = getBearerToken().trim();
    if (bearerToken.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $bearerToken';
    }

    if (jobId != null && pageIndex != null) {
      request.fields['job_id'] = jobId;
      request.fields['page_index'] = pageIndex.toString();
    }

    final streamedResponse = await _httpClient
        .send(request)
        .timeout(_timeoutDuration);
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      throw _errorFromResponse(response);
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

  /// Build an [OcrServerException] from a FastAPI-style error response.
  ///
  /// `detail` may be a plain string or a structured object like
  /// `{"code": "job_expired", "message": "The OCR job has expired."}`.
  static OcrServerException _errorFromResponse(http.Response response) {
    var message = response.body;
    String? code;
    try {
      final body = json.decode(response.body) as Map<String, dynamic>;
      final detail = body['detail'];
      if (detail is String) {
        message = detail;
      } else if (detail is Map<String, dynamic>) {
        message = detail['message'] as String? ?? response.body;
        code = detail['code'] as String?;
      }
    } catch (_) {
      // Not JSON — keep the raw body as the message.
    }
    return OcrServerException(
      response.statusCode,
      message,
      code: code,
      retryAfter: _parseRetryAfter(response.headers['retry-after']),
    );
  }

  static Duration? _parseRetryAfter(String? headerValue) {
    if (headerValue == null) return null;
    final seconds = int.tryParse(headerValue.trim());
    if (seconds == null || seconds < 0) return null;
    return Duration(seconds: seconds);
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
