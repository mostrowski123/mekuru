import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ocr_server_config.dart' as ocr_server_config;

class OcrServerHealthResult {
  final String status;

  const OcrServerHealthResult({required this.status});
}

class OcrServerHealthException implements Exception {
  final int statusCode;
  final String message;

  const OcrServerHealthException(this.statusCode, this.message);

  @override
  String toString() => 'OcrServerHealthException($statusCode): $message';
}

class OcrServerHealthClient {
  final http.Client _httpClient;
  final Duration _timeout;

  OcrServerHealthClient({
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 5),
  }) : _httpClient = httpClient ?? http.Client(),
       _timeout = timeout;

  Future<OcrServerHealthResult> checkHealth(String serverUrl) async {
    final normalized = ocr_server_config.normalizeOcrServerUrl(serverUrl);
    final urlError = ocr_server_config.validateOcrServerUrl(normalized);
    if (urlError != null) {
      final message = normalized.isEmpty
          ? 'OCR server URL is not configured.'
          : 'OCR server URL is invalid. Use a full http:// or https:// URL.';
      throw OcrServerHealthException(0, message);
    }

    final baseUri = ocr_server_config.tryParseOcrServerUrl(normalized);
    if (baseUri == null) {
      throw const OcrServerHealthException(
        0,
        'OCR server URL is invalid. Use a full http:// or https:// URL.',
      );
    }

    final uri = baseUri.replace(
      path: '${baseUri.path}/health'.replaceAll('//', '/'),
    );

    try {
      final response = await _httpClient.get(uri).timeout(_timeout);
      if (response.statusCode != 200) {
        throw OcrServerHealthException(
          response.statusCode,
          _describeErrorResponse(response),
        );
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final status = (data['status'] as String?)?.trim();
      if (status == null || status.isEmpty) {
        throw const OcrServerHealthException(
          200,
          'Server returned an unexpected health response.',
        );
      }
      if (status.toLowerCase() != 'ok') {
        throw OcrServerHealthException(
          200,
          'Server reported health status "$status" instead of "ok".',
        );
      }

      return OcrServerHealthResult(status: status);
    } on TimeoutException {
      throw const OcrServerHealthException(
        0,
        'OCR server did not respond in time.',
      );
    } on OcrServerHealthException {
      rethrow;
    } on Exception catch (e) {
      throw OcrServerHealthException(0, 'Could not connect to OCR server: $e');
    }
  }

  void dispose() {
    _httpClient.close();
  }

  String _describeErrorResponse(http.Response response) {
    try {
      final body = json.decode(response.body) as Map<String, dynamic>;
      final detail = (body['detail'] as String?)?.trim();
      if (detail != null && detail.isNotEmpty) {
        return detail;
      }
    } catch (_) {
      // Fall back to the raw body below.
    }

    final body = response.body.trim();
    if (body.isNotEmpty) {
      return body;
    }

    return 'OCR server returned HTTP ${response.statusCode}.';
  }
}
