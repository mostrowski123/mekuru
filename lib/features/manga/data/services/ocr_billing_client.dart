import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../../../../core/services/firebase_runtime.dart';
import '../../../../firebase_options.dart';

const _androidPackageName = 'moe.matthew.mekuru';
const _billingFunctionsRegion = 'us-central1';
const _billingFunctionsName = 'billingApiV2';
const _billingFunctionsBaseUrlOverride = String.fromEnvironment(
  'OCR_BILLING_FUNCTIONS_BASE_URL',
);

class OcrBillingStatus {
  final bool ocrUnlocked;
  final int creditBalance;

  const OcrBillingStatus({
    required this.ocrUnlocked,
    required this.creditBalance,
  });
}

class PurchaseGrantResult {
  final bool ocrUnlocked;
  final int creditBalance;
  final int grantedCredits;

  const PurchaseGrantResult({
    required this.ocrUnlocked,
    required this.creditBalance,
    required this.grantedCredits,
  });
}

class OcrJobReservation {
  final String jobId;
  final int reservedPages;
  final DateTime expiresAt;
  final int creditBalance;

  const OcrJobReservation({
    required this.jobId,
    required this.reservedPages,
    required this.expiresAt,
    required this.creditBalance,
  });
}

class OcrJobFinalization {
  final int completedPages;
  final int refundedPages;
  final int creditBalance;

  const OcrJobFinalization({
    required this.completedPages,
    required this.refundedPages,
    required this.creditBalance,
  });
}

class OcrBillingException implements Exception {
  final int statusCode;
  final String message;
  final String? code;
  final int? requiredCredits;
  final int? availableCredits;

  const OcrBillingException(
    this.statusCode,
    this.message, {
    this.code,
    this.requiredCredits,
    this.availableCredits,
  });

  bool get isUnlockRequired => code == 'unlock_required';
  bool get isInsufficientCredits => code == 'insufficient_credits';

  @override
  String toString() => 'OcrBillingException($statusCode, $code): $message';
}

String describeOcrError(Object error) {
  if (error is OcrBillingException) {
    return error.message;
  }

  if (error is FirebaseAuthException) {
    return error.message ?? 'Authentication failed.';
  }

  if (error is StateError) {
    return error.message.toString();
  }

  return error.toString();
}

class OcrBillingClient {
  static const _cachedStatusKey = 'ocr.billing.status';
  static const OcrBillingException _networkUnavailableError =
      OcrBillingException(
        0,
        'No internet connection. Check your connection and try again.',
        code: 'network_unavailable',
      );
  static final FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: const AndroidOptions(encryptedSharedPreferences: true),
  );

  final http.Client _httpClient;
  final Duration requestTimeout;
  final Duration baseRetryDelay;

  OcrBillingClient({
    http.Client? httpClient,
    this.requestTimeout = const Duration(seconds: 15),
    this.baseRetryDelay = const Duration(seconds: 1),
  }) : _httpClient = httpClient ?? http.Client();

  void _log(String message, [Map<String, Object?> details = const {}]) {
    final suffix = details.isEmpty ? '' : ' $details';
    debugPrint('[OcrBillingClient] $message$suffix');
  }

  Future<OcrBillingStatus?> readCachedStatus() async {
    if (!FirebaseRuntime.instance.hasFirebaseApp) {
      return null;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return null;
    }

    try {
      final raw = await _secureStorage.read(key: _cachedStatusKey);
      if (raw == null || raw.isEmpty) {
        return null;
      }

      final decoded = json.decode(raw) as Map<String, dynamic>;
      if (decoded['uid'] != user.uid) {
        await _secureStorage.delete(key: _cachedStatusKey);
        _log('cleared stale cached status', {'cachedUid': decoded['uid']});
        return null;
      }

      // Treat cache as stale after 24 hours.
      final cachedAt = decoded['cachedAt'] as String?;
      if (cachedAt != null) {
        final age = DateTime.now().toUtc().difference(DateTime.parse(cachedAt));
        if (age > const Duration(hours: 24)) {
          _log('cached status expired', {'age': age.toString()});
          return null;
        }
      }

      final status = OcrBillingStatus(
        ocrUnlocked: decoded['ocrUnlocked'] as bool? ?? false,
        creditBalance: decoded['creditBalance'] as int? ?? 0,
      );
      _log('cached status hit', {
        'ocrUnlocked': status.ocrUnlocked,
        'creditBalance': status.creditBalance,
      });
      return status;
    } catch (e) {
      _log('failed to read cached status', {'error': e.toString()});
      return null;
    }
  }

  Future<OcrBillingStatus> fetchStatus({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = await readCachedStatus();
      if (cached != null) {
        return cached;
      }
    }

    try {
      final response = await _withRetry(
        () => _sendJsonRequest(method: 'GET', path: '/billing/status'),
      );
      final status = OcrBillingStatus(
        ocrUnlocked: response['ocrUnlocked'] as bool? ?? false,
        creditBalance: response['creditBalance'] as int? ?? 0,
      );
      await _writeCachedStatus(status);
      return status;
    } on OcrBillingException catch (e) {
      await _applyErrorStatusHint(e);
      rethrow;
    }
  }

  Future<PurchaseGrantResult> verifyAndroidPurchase({
    required String productId,
    required String purchaseToken,
    String? orderId,
    bool isRestore = false,
  }) async {
    try {
      final response = await _withRetry(
        () => _sendJsonRequest(
          method: 'POST',
          path: '/billing/purchases/android/verify',
          body: {
            'productId': productId,
            'purchaseToken': purchaseToken,
            'orderId': orderId,
            'packageName': _androidPackageName,
            'isRestore': isRestore,
          },
        ),
      );
      final result = PurchaseGrantResult(
        ocrUnlocked: response['ocrUnlocked'] as bool? ?? false,
        creditBalance: response['creditBalance'] as int? ?? 0,
        grantedCredits: response['grantedCredits'] as int? ?? 0,
      );
      await _writeCachedStatus(
        OcrBillingStatus(
          ocrUnlocked: result.ocrUnlocked,
          creditBalance: result.creditBalance,
        ),
      );
      return result;
    } on OcrBillingException catch (e) {
      await _applyErrorStatusHint(e);
      rethrow;
    }
  }

  Future<OcrJobReservation> reserveOcrJob({
    required int requestedPages,
    required int bookId,
  }) async {
    try {
      final response = await _withRetry(
        () => _sendJsonRequest(
          method: 'POST',
          path: '/ocr/jobs',
          body: {'requestedPages': requestedPages, 'bookId': bookId},
        ),
      );
      final reservation = OcrJobReservation(
        jobId: response['jobId'] as String? ?? '',
        reservedPages: response['reservedPages'] as int? ?? 0,
        expiresAt: DateTime.parse(response['expiresAt'] as String),
        creditBalance: response['creditBalance'] as int? ?? 0,
      );
      await _writeCachedStatus(
        OcrBillingStatus(
          ocrUnlocked: true,
          creditBalance: reservation.creditBalance,
        ),
      );
      return reservation;
    } on OcrBillingException catch (e) {
      await _applyErrorStatusHint(e);
      rethrow;
    }
  }

  Future<OcrJobFinalization> finalizeOcrJob({
    required String jobId,
    required String status,
  }) async {
    try {
      final response = await _withRetry(
        () => _sendJsonRequest(
          method: 'POST',
          path: '/ocr/jobs/$jobId/finalize',
          body: {'status': status},
        ),
      );
      final finalization = OcrJobFinalization(
        completedPages: response['completedPages'] as int? ?? 0,
        refundedPages: response['refundedPages'] as int? ?? 0,
        creditBalance: response['creditBalance'] as int? ?? 0,
      );
      await _writeCachedStatus(
        OcrBillingStatus(
          ocrUnlocked: true,
          creditBalance: finalization.creditBalance,
        ),
      );
      return finalization;
    } on OcrBillingException catch (e) {
      await _applyErrorStatusHint(e);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _sendJsonRequest({
    required String method,
    required String path,
    Map<String, dynamic>? body,
  }) async {
    final serverUrl = _billingBaseUrl();
    final token = await _getIdToken();
    final uri = Uri.parse('$serverUrl$path');
    final request = http.Request(method, uri);
    request.headers['Authorization'] = 'Bearer $token';
    request.headers['Content-Type'] = 'application/json';
    if (body != null) {
      request.body = json.encode(body);
    }

    _log('request', {
      'method': method,
      'url': uri.toString(),
      'body': body == null ? null : _redactRequestBody(body),
    });

    try {
      final streamed = await _httpClient.send(request).timeout(requestTimeout);
      final response = await http.Response.fromStream(
        streamed,
      ).timeout(requestTimeout);

      _log('response', {
        'method': method,
        'url': uri.toString(),
        'statusCode': response.statusCode,
        'body': response.body,
      });

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _parseError(response);
      }

      if (response.body.isEmpty) return <String, dynamic>{};
      return json.decode(response.body) as Map<String, dynamic>;
    } on SocketException {
      throw _networkUnavailableError;
    } on TimeoutException {
      throw _networkUnavailableError;
    }
  }

  Future<T> _withRetry<T>(Future<T> Function() action) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return await action();
      } on OcrBillingException catch (error) {
        if (!_shouldRetry(error) || attempt == 2) {
          rethrow;
        }
      } on SocketException {
        if (attempt == 2) {
          throw _networkUnavailableError;
        }
      } on TimeoutException {
        if (attempt == 2) {
          throw _networkUnavailableError;
        }
      }

      await Future<void>.delayed(baseRetryDelay * (1 << attempt));
    }

    throw StateError('Billing retry loop exited unexpectedly.');
  }

  bool _shouldRetry(OcrBillingException error) {
    if (error.code == 'network_unavailable') {
      return true;
    }

    return error.statusCode >= 500 && error.statusCode < 600;
  }

  Map<String, dynamic> _redactRequestBody(Map<String, dynamic> body) {
    final copy = <String, dynamic>{...body};
    final purchaseToken = copy['purchaseToken'];
    if (purchaseToken is String && purchaseToken.isNotEmpty) {
      copy['purchaseToken'] = purchaseToken.length <= 8
          ? purchaseToken
          : '...${purchaseToken.substring(purchaseToken.length - 8)}';
    }
    return copy;
  }

  String _billingBaseUrl() {
    if (_billingFunctionsBaseUrlOverride.isNotEmpty) {
      return _billingFunctionsBaseUrlOverride;
    }

    final projectId = DefaultFirebaseOptions.currentPlatform.projectId;
    return 'https://$_billingFunctionsRegion-$projectId.cloudfunctions.net/$_billingFunctionsName';
  }

  Future<String> _getIdToken() async {
    final user = await FirebaseRuntime.instance.ensureOcrUser();
    final token = await user.getIdToken(true);
    if (token == null || token.isEmpty) {
      throw const OcrBillingException(
        401,
        'Failed to refresh the Firebase ID token for OCR billing.',
        code: 'auth_required',
      );
    }
    return token;
  }

  OcrBillingException _parseError(http.Response response) {
    try {
      final decoded = json.decode(response.body) as Map<String, dynamic>;
      final detail = decoded['detail'];
      if (detail is Map<String, dynamic>) {
        return OcrBillingException(
          response.statusCode,
          detail['message'] as String? ?? 'OCR billing request failed.',
          code: detail['code'] as String?,
          requiredCredits: detail['requiredCredits'] as int?,
          availableCredits: detail['availableCredits'] as int?,
        );
      }
      if (detail is String) {
        return OcrBillingException(response.statusCode, detail);
      }
    } catch (_) {
      // Response body was not valid JSON — fall through to generic error.
    }

    return OcrBillingException(
      response.statusCode,
      response.body.isEmpty ? 'OCR billing request failed.' : response.body,
    );
  }

  Future<void> _writeCachedStatus(OcrBillingStatus status) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    try {
      await _secureStorage.write(
        key: _cachedStatusKey,
        value: json.encode({
          'uid': user.uid,
          'ocrUnlocked': status.ocrUnlocked,
          'creditBalance': status.creditBalance,
          'cachedAt': DateTime.now().toUtc().toIso8601String(),
        }),
      );
      _log('cached status updated', {
        'ocrUnlocked': status.ocrUnlocked,
        'creditBalance': status.creditBalance,
      });
    } catch (e) {
      _log('failed to write cached status', {'error': e.toString()});
    }
  }

  Future<void> _clearCachedStatus() async {
    try {
      await _secureStorage.delete(key: _cachedStatusKey);
      _log('cached status cleared');
    } catch (e) {
      _log('failed to clear cached status', {'error': e.toString()});
    }
  }

  Future<void> _applyErrorStatusHint(OcrBillingException error) async {
    final cached = await readCachedStatus();

    if (error.code == 'auth_required') {
      await _clearCachedStatus();
      return;
    }

    if (error.code == 'unlock_required') {
      await _writeCachedStatus(
        OcrBillingStatus(
          ocrUnlocked: false,
          creditBalance: cached?.creditBalance ?? 0,
        ),
      );
      return;
    }

    if (error.code == 'insufficient_credits') {
      await _writeCachedStatus(
        OcrBillingStatus(
          ocrUnlocked: cached?.ocrUnlocked ?? true,
          creditBalance: error.availableCredits ?? cached?.creditBalance ?? 0,
        ),
      );
    }
  }

  void dispose() {
    _httpClient.close();
  }
}
