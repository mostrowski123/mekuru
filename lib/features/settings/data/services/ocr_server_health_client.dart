import 'dart:io';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mekuru/core/services/server_http_client.dart';
import 'package:mekuru/core/services/http_transport.dart';
import 'package:mekuru/features/manga/data/services/ocr_failure.dart';

import 'ocr_server_config.dart' as ocr_server_config;

class OcrServerHealthResult {
  final String status;

  const OcrServerHealthResult({required this.status});
}

class OcrServerHealthException implements Exception {
  final int statusCode;

  /// An [OcrFailure] code, worded for the user by `describeOcrFailure`.
  final String failure;

  const OcrServerHealthException(this.statusCode, this.failure);

  @override
  String toString() => 'OcrServerHealthException($statusCode): $failure';
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
    final baseUri = urlError == null
        ? ocr_server_config.tryParseOcrServerUrl(normalized)
        : null;
    if (baseUri == null) {
      throw OcrServerHealthException(0, OcrFailure.serverUrlInvalid.code());
    }

    final uri = baseUri.replace(
      path: '${baseUri.path}/health'.replaceAll('//', '/'),
    );

    try {
      final response = await sendWithTimeout(
        _httpClient,
        http.Request('GET', uri),
        timeout: _timeout,
      );
      if (response.statusCode != 200) {
        throw OcrServerHealthException(
          response.statusCode,
          _describeErrorResponse(response),
        );
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final status = (data['status'] as String?)?.trim();
      if (status == null || status.isEmpty) {
        throw OcrServerHealthException(
          200,
          OcrFailure.malformedResponse.code(),
        );
      }
      if (status.toLowerCase() != 'ok') {
        throw OcrServerHealthException(200, OcrFailure.unhealthy.code(status));
      }

      return OcrServerHealthResult(status: status);
    } on NetworkException catch (e) {
      throw OcrServerHealthException(
        0,
        e.timedOut
            ? OcrFailure.timedOut.code()
            : ocrNetworkErrorCode(e.message),
      );
    } on OcrServerHealthException {
      rethrow;
    } on HandshakeException catch (e) {
      // The dialog explains a rejected certificate itself.
      if (isUntrustedCertificateError(e)) rethrow;
      throw OcrServerHealthException(0, ocrNetworkErrorCode('$e'));
    } catch (e) {
      // A body that isn't the JSON /health sends: malformed.
      throw OcrServerHealthException(0, ocrErrorCode(e));
    }
  }

  void dispose() {
    _httpClient.close();
  }

  /// [response]'s error status as an [OcrFailure] code, with the server's
  /// explanation when it gave one.
  String _describeErrorResponse(http.Response response) {
    var detail = response.body.trim();
    try {
      final body = json.decode(response.body) as Map<String, dynamic>;
      detail = (body['detail'] as String?)?.trim() ?? detail;
    } catch (_) {
      // Not JSON: the raw body is the explanation.
    }
    return detail.isEmpty && response.statusCode >= 500
        ? OcrFailure.serverError.code(response.statusCode)
        : OcrFailure.status.code('${response.statusCode}:$detail');
  }
}
