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
const _entitlementRefreshInterval = Duration(hours: 24);

abstract class OcrBillingStatusStorage {
  Future<String?> read({required String key});
  Future<void> write({required String key, required String value});
  Future<void> delete({required String key});
}

class SecureOcrBillingStatusStorage implements OcrBillingStatusStorage {
  SecureOcrBillingStatusStorage({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;

  @override
  Future<String?> read({required String key}) {
    return _secureStorage.read(key: key);
  }

  @override
  Future<void> write({required String key, required String value}) {
    return _secureStorage.write(key: key, value: value);
  }

  @override
  Future<void> delete({required String key}) {
    return _secureStorage.delete(key: key);
  }
}

class OcrBillingStatus {
  final bool ocrUnlocked;
  final int creditBalance;

  const OcrBillingStatus({
    required this.ocrUnlocked,
    required this.creditBalance,
  });
}

class OcrBillingCacheSnapshot {
  const OcrBillingCacheSnapshot({
    required this.ocrUnlocked,
    required this.creditBalance,
    this.uid,
    this.cachedAt,
  });

  final String? uid;
  final bool ocrUnlocked;
  final int creditBalance;
  final DateTime? cachedAt;

  OcrBillingStatus get status =>
      OcrBillingStatus(ocrUnlocked: ocrUnlocked, creditBalance: creditBalance);

  bool isRefreshDue({
    required DateTime now,
    Duration refreshInterval = _entitlementRefreshInterval,
  }) {
    final cachedAt = this.cachedAt;
    if (cachedAt == null) {
      return true;
    }
    return now.toUtc().difference(cachedAt.toUtc()) >= refreshInterval;
  }
}

class PreloadedProEntitlement {
  static OcrBillingCacheSnapshot? initialSnapshot;

  static OcrBillingStatus? get initialStatus => initialSnapshot?.status;

  static bool get isInitiallyUnlocked => initialStatus?.ocrUnlocked ?? false;

  static Future<void> load({OcrBillingClient? billingClient}) async {
    final ownedClient = billingClient ?? OcrBillingClient();
    try {
      initialSnapshot = await ownedClient.readLastKnownSnapshot();
    } finally {
      if (billingClient == null) {
        ownedClient.dispose();
      }
    }
  }

  static void setInitialSnapshot(OcrBillingCacheSnapshot? snapshot) {
    initialSnapshot = snapshot;
  }
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
    if (error.code == 'too-many-requests') {
      return 'Too many recent sign-in attempts. Wait a few minutes, then try again.';
    }
    return error.message ?? 'Authentication failed.';
  }

  if (error is FirebaseException) {
    final message = error.message?.toLowerCase() ?? '';
    if (error.code == 'too-many-requests' ||
        message.contains('too many attempts')) {
      return 'Firebase App Check is temporarily rate limited. '
          'Wait a few minutes before trying again.';
    }
    if (message.contains('app attestation failed')) {
      return 'Firebase App Check failed for this build. '
          'If this is a local test build, enable the debug App Check provider.';
    }
    return error.message ?? 'Firebase request failed.';
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

  final http.Client _httpClient;
  final OcrBillingStatusStorage _statusStorage;
  final DateTime Function() _now;
  final Future<void> Function() _ensureFirebaseApp;
  final String? Function() _readCurrentUid;
  final Duration requestTimeout;
  final Duration baseRetryDelay;

  OcrBillingClient({
    http.Client? httpClient,
    OcrBillingStatusStorage? statusStorage,
    DateTime Function()? now,
    Future<void> Function()? ensureFirebaseApp,
    String? Function()? readCurrentUid,
    this.requestTimeout = const Duration(seconds: 15),
    this.baseRetryDelay = const Duration(seconds: 1),
  }) : _httpClient = httpClient ?? http.Client(),
       _statusStorage = statusStorage ?? SecureOcrBillingStatusStorage(),
       _now = now ?? DateTime.now,
       _ensureFirebaseApp =
           ensureFirebaseApp ?? FirebaseRuntime.instance.ensureFirebaseApp,
       _readCurrentUid =
           readCurrentUid ?? (() => FirebaseAuth.instance.currentUser?.uid);

  void _log(String message, [Map<String, Object?> details = const {}]) {
    final suffix = details.isEmpty ? '' : ' $details';
    debugPrint('[OcrBillingClient] $message$suffix');
  }

  Future<OcrBillingCacheSnapshot?> readLastKnownSnapshot() async {
    try {
      final raw = await _statusStorage.read(key: _cachedStatusKey);
      if (raw == null || raw.isEmpty) {
        return null;
      }

      final decoded = json.decode(raw) as Map<String, dynamic>;
      final snapshot = OcrBillingCacheSnapshot(
        uid: decoded['uid'] as String?,
        ocrUnlocked: decoded['ocrUnlocked'] as bool? ?? false,
        creditBalance: decoded['creditBalance'] as int? ?? 0,
        cachedAt: _parseCachedAt(decoded['cachedAt'] as String?),
      );
      _log('cached status hit', {
        'uid': snapshot.uid,
        'ocrUnlocked': snapshot.ocrUnlocked,
        'creditBalance': snapshot.creditBalance,
        'cachedAt': snapshot.cachedAt?.toIso8601String(),
      });
      return snapshot;
    } catch (e) {
      _log('failed to read cached status', {'error': e.toString()});
      return null;
    }
  }

  Future<OcrBillingStatus?> readLastKnownStatus() async {
    return (await readLastKnownSnapshot())?.status;
  }

  Future<bool> isRefreshDue() async {
    final snapshot = await readLastKnownSnapshot();
    if (snapshot == null) {
      return true;
    }
    return snapshot.isRefreshDue(now: _now());
  }

  Future<OcrBillingStatus?> readCachedStatus() async {
    final snapshot = await readLastKnownSnapshot();
    if (snapshot == null) {
      return null;
    }

    final currentUid = _readCurrentUid();
    if (currentUid != null &&
        snapshot.uid != null &&
        snapshot.uid != currentUid) {
      await _clearCachedStatus();
      _log('cleared cached status for another user', {
        'cachedUid': snapshot.uid,
        'currentUid': currentUid,
      });
      return null;
    }

    return snapshot.status;
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
        () => _sendJsonRequest(
          method: 'GET',
          path: '/billing/status',
          requireAppCheck: false,
        ),
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

  Future<OcrBillingStatus?> fetchStatusIfAuthenticated({
    bool forceRefresh = false,
  }) async {
    return refreshStatusIfAuthenticated(forceRefresh: forceRefresh);
  }

  Future<OcrBillingStatus?> refreshStatusIfAuthenticated({
    bool forceRefresh = false,
  }) async {
    final cached = await readCachedStatus();
    if (!forceRefresh && !await isRefreshDue()) {
      return cached;
    }

    try {
      await _ensureFirebaseApp();
    } catch (e) {
      _log('skipping passive status refresh', {'error': e.toString()});
      return null;
    }

    final currentUid = _readCurrentUid();
    if (currentUid == null) {
      _log('skipping passive status refresh: no signed-in Firebase user');
      return null;
    }

    final snapshot = await readLastKnownSnapshot();
    if (snapshot?.uid != null && snapshot!.uid != currentUid) {
      await _clearCachedStatus();
    }

    return fetchStatus(forceRefresh: true);
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
          requireAppCheck: false,
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
          requireAppCheck: true,
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
          requireAppCheck: true,
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
    required bool requireAppCheck,
    Map<String, dynamic>? body,
  }) async {
    final serverUrl = _billingBaseUrl();
    final token = await _getIdToken();
    final uri = Uri.parse('$serverUrl$path');
    final request = http.Request(method, uri);
    request.headers['Authorization'] = 'Bearer $token';
    if (requireAppCheck) {
      request.headers['X-Firebase-AppCheck'] = await _getAppCheckToken();
    }
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
    await _ensureFirebaseApp();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const OcrBillingException(
        401,
        'Sign in with Google before using OCR billing features.',
        code: 'auth_required',
      );
    }
    final token = await user.getIdToken(true);
    if (token == null || token.isEmpty) {
      throw const OcrBillingException(
        401,
        'Sign in with Google before using OCR billing features.',
        code: 'auth_required',
      );
    }
    return token;
  }

  Future<String> _getAppCheckToken() async {
    try {
      final token = await FirebaseRuntime.instance.getAppCheckToken();
      if (token == null || token.isEmpty) {
        throw const OcrBillingException(
          401,
          'Failed to refresh the Firebase App Check token for OCR billing.',
          code: 'app_check_required',
        );
      }
      return token;
    } on FirebaseException catch (error) {
      final message = error.message?.toLowerCase() ?? '';
      if (error.code == 'too-many-requests' ||
          message.contains('too many attempts')) {
        throw const OcrBillingException(
          429,
          'Firebase App Check is temporarily rate limited. '
          'Wait a few minutes before trying again.',
          code: 'app_check_rate_limited',
        );
      }
      if (message.contains('app attestation failed')) {
        throw const OcrBillingException(
          401,
          'Firebase App Check failed for this build. '
          'If you are testing a local build, enable the debug App Check provider.',
          code: 'app_check_attestation_failed',
        );
      }
      throw const OcrBillingException(
        401,
        'Failed to refresh the Firebase App Check token for OCR billing.',
        code: 'app_check_required',
      );
    }
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
    final currentUid = _readCurrentUid();
    if (currentUid == null) {
      return;
    }

    try {
      final snapshot = OcrBillingCacheSnapshot(
        uid: currentUid,
        ocrUnlocked: status.ocrUnlocked,
        creditBalance: status.creditBalance,
        cachedAt: _now().toUtc(),
      );
      await _statusStorage.write(
        key: _cachedStatusKey,
        value: json.encode({
          'uid': snapshot.uid,
          'ocrUnlocked': snapshot.ocrUnlocked,
          'creditBalance': snapshot.creditBalance,
          'cachedAt': snapshot.cachedAt?.toIso8601String(),
        }),
      );
      PreloadedProEntitlement.setInitialSnapshot(snapshot);
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
      await _statusStorage.delete(key: _cachedStatusKey);
      PreloadedProEntitlement.setInitialSnapshot(null);
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

  @visibleForTesting
  Future<void> cacheStatusForTesting(OcrBillingStatus status) {
    return _writeCachedStatus(status);
  }

  @visibleForTesting
  Future<void> applyErrorStatusHintForTesting(OcrBillingException error) {
    return _applyErrorStatusHint(error);
  }

  void dispose() {
    _httpClient.close();
  }
}

DateTime? _parseCachedAt(String? raw) {
  if (raw == null || raw.isEmpty) {
    return null;
  }

  try {
    return DateTime.parse(raw);
  } catch (_) {
    return null;
  }
}
