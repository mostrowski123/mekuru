import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/data/services/ocr_billing_client.dart';

const _cachedStatusKey = 'ocr.billing.status';

class _FakeStatusStorage implements OcrBillingStatusStorage {
  _FakeStatusStorage([Map<String, String>? initialValues])
    : values = {...?initialValues};

  final Map<String, String> values;

  @override
  Future<String?> read({required String key}) async {
    return values[key];
  }

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }
}

class _RefreshingBillingClient extends OcrBillingClient {
  _RefreshingBillingClient({
    required super.statusStorage,
    required super.now,
    required super.ensureFirebaseApp,
    required super.readCurrentUid,
    required this.refreshedStatus,
  });

  final OcrBillingStatus refreshedStatus;

  int fetchStatusCalls = 0;

  @override
  Future<OcrBillingStatus> fetchStatus({bool forceRefresh = false}) async {
    fetchStatusCalls++;
    await cacheStatusForTesting(refreshedStatus);
    return refreshedStatus;
  }
}

void main() {
  tearDown(() {
    PreloadedProEntitlement.setInitialSnapshot(null);
  });

  test(
    'readLastKnownStatus returns the local snapshot without Firebase auth',
    () async {
      final storage = _FakeStatusStorage({
        _cachedStatusKey: json.encode({
          'uid': 'user-1',
          'ocrUnlocked': true,
          'creditBalance': 500,
          'cachedAt': '2026-03-10T00:00:00.000Z',
        }),
      });
      final client = OcrBillingClient(statusStorage: storage);

      final status = await client.readLastKnownStatus();

      expect(status, isNotNull);
      expect(status!.ocrUnlocked, isTrue);
      expect(status.creditBalance, 500);
    },
  );

  test(
    'stale local snapshots remain usable but are marked refresh due',
    () async {
      final now = DateTime.utc(2026, 3, 12, 12);
      final storage = _FakeStatusStorage({
        _cachedStatusKey: json.encode({
          'uid': 'user-1',
          'ocrUnlocked': true,
          'creditBalance': 500,
          'cachedAt': now.subtract(const Duration(days: 2)).toIso8601String(),
        }),
      });
      final client = OcrBillingClient(statusStorage: storage, now: () => now);

      final status = await client.readLastKnownStatus();

      expect(status?.ocrUnlocked, isTrue);
      expect(await client.isRefreshDue(), isTrue);
    },
  );

  test(
    'refreshStatusIfAuthenticated updates the cached snapshot and timestamp',
    () async {
      final now = DateTime.utc(2026, 3, 12, 12);
      final storage = _FakeStatusStorage({
        _cachedStatusKey: json.encode({
          'uid': 'user-1',
          'ocrUnlocked': false,
          'creditBalance': 0,
          'cachedAt': now.subtract(const Duration(days: 2)).toIso8601String(),
        }),
      });
      final client = _RefreshingBillingClient(
        statusStorage: storage,
        now: () => now,
        ensureFirebaseApp: () async {},
        readCurrentUid: () => 'user-1',
        refreshedStatus: const OcrBillingStatus(
          ocrUnlocked: true,
          creditBalance: 500,
        ),
      );

      final refreshed = await client.refreshStatusIfAuthenticated();
      final decoded =
          json.decode(storage.values[_cachedStatusKey]!)
              as Map<String, dynamic>;

      expect(refreshed?.ocrUnlocked, isTrue);
      expect(refreshed?.creditBalance, 500);
      expect(client.fetchStatusCalls, 1);
      expect(decoded['ocrUnlocked'], isTrue);
      expect(decoded['creditBalance'], 500);
      expect(decoded['cachedAt'], now.toIso8601String());
    },
  );

  test(
    'unlock_required relocks the cached snapshot without losing credits',
    () async {
      final storage = _FakeStatusStorage();
      final client = OcrBillingClient(
        statusStorage: storage,
        readCurrentUid: () => 'user-1',
      );
      await client.cacheStatusForTesting(
        const OcrBillingStatus(ocrUnlocked: true, creditBalance: 500),
      );

      await client.applyErrorStatusHintForTesting(
        const OcrBillingException(
          403,
          'Pro unlock required.',
          code: 'unlock_required',
        ),
      );

      final status = await client.readLastKnownStatus();

      expect(status, isNotNull);
      expect(status!.ocrUnlocked, isFalse);
      expect(status.creditBalance, 500);
    },
  );

  test('auth_required clears the cached snapshot', () async {
    final storage = _FakeStatusStorage();
    final client = OcrBillingClient(
      statusStorage: storage,
      readCurrentUid: () => 'user-1',
    );
    await client.cacheStatusForTesting(
      const OcrBillingStatus(ocrUnlocked: true, creditBalance: 500),
    );

    await client.applyErrorStatusHintForTesting(
      const OcrBillingException(401, 'Sign in first.', code: 'auth_required'),
    );

    expect(await client.readLastKnownStatus(), isNull);
    expect(storage.values, isEmpty);
  });

  test('describeOcrError maps App Check rate limiting to retry guidance', () {
    final error = FirebaseException(
      plugin: 'firebase_app_check',
      code: 'too-many-requests',
      message: 'Too many attempts.',
    );

    expect(
      describeOcrError(error),
      'Firebase App Check is temporarily rate limited. '
      'Wait a few minutes before trying again.',
    );
  });

  test(
    'describeOcrError maps App Check attestation failures to build guidance',
    () {
      final error = FirebaseException(
        plugin: 'firebase_app_check',
        code: 'unknown',
        message:
            'Error returned from API. code: 403 body: App attestation failed.',
      );

      expect(
        describeOcrError(error),
        'Firebase App Check failed for this build. '
        'If this is a local test build, enable the debug App Check provider.',
      );
    },
  );
}
