import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:mekuru/features/manga/data/services/ocr_billing_client.dart';
import 'package:mekuru/features/manga/data/services/ocr_store_service.dart';

const _playEntitlementKey = 'ocr.play_entitlement';

GooglePlayPurchaseDetails _purchase({
  required String productId,
  required PurchaseStateWrapper purchaseState,
  PurchaseStatus status = PurchaseStatus.purchased,
  bool pendingComplete = false,
}) {
  return GooglePlayPurchaseDetails(
    purchaseID: 'order-1',
    productID: productId,
    verificationData: PurchaseVerificationData(
      localVerificationData: '{}',
      serverVerificationData: 'token-1',
      source: 'google_play',
    ),
    transactionDate: '0',
    billingClientPurchase: PurchaseWrapper(
      orderId: 'order-1',
      packageName: 'moe.matthew.mekuru',
      purchaseTime: 0,
      purchaseToken: 'token-1',
      signature: 'sig',
      products: <String>[productId],
      isAutoRenewing: false,
      originalJson: '{}',
      isAcknowledged: false,
      purchaseState: purchaseState,
    ),
    status: status,
  )..pendingCompletePurchase = pendingComplete;
}

/// An owned, paid, not-yet-acknowledged pro purchase as the purchase stream
/// delivers it after a live buy.
GooglePlayPurchaseDetails _ownedProPurchase({bool pendingComplete = true}) =>
    _purchase(
      productId: proUnlockProductId,
      purchaseState: PurchaseStateWrapper.purchased,
      pendingComplete: pendingComplete,
    );

/// The credit-consumable twin of [_ownedProPurchase].
GooglePlayPurchaseDetails _creditPurchase({bool pendingComplete = true}) =>
    _purchase(
      productId: ocrCredit500ProductId,
      purchaseState: PurchaseStateWrapper.purchased,
      pendingComplete: pendingComplete,
    );

class _FakeStatusStorage implements OcrBillingStatusStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }
}

class _FakeAndroidAddition implements InAppPurchaseAndroidPlatformAddition {
  QueryPurchaseDetailsResponse Function() onQueryPastPurchases = () =>
      QueryPurchaseDetailsResponse(pastPurchases: const []);
  int queryPastPurchasesCalls = 0;

  @override
  Future<QueryPurchaseDetailsResponse> queryPastPurchases({
    String? applicationUserName,
  }) async {
    queryPastPurchasesCalls++;
    return onQueryPastPurchases();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('$invocation');
}

class _FakeInAppPurchase implements InAppPurchase {
  _FakeInAppPurchase(this.callLog);

  final List<String> callLog;
  final _FakeAndroidAddition addition = _FakeAndroidAddition();
  // Broadcast to match the real purchaseStream (and so close() cannot hang
  // when a test never subscribed).
  final StreamController<List<PurchaseDetails>> purchaseUpdates =
      StreamController<List<PurchaseDetails>>.broadcast();

  bool available = true;
  Object? isAvailableError;
  int isAvailableCalls = 0;
  bool buyStarts = true;
  void Function(PurchaseParam param)? onBuy;
  Object? completePurchaseError;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => purchaseUpdates.stream;

  @override
  Future<bool> isAvailable() async {
    isAvailableCalls++;
    final error = isAvailableError;
    if (error != null) throw error;
    return available;
  }

  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> identifiers,
  ) async {
    return ProductDetailsResponse(
      productDetails: [
        for (final id in identifiers)
          ProductDetails(
            id: id,
            title: id,
            description: id,
            price: '¥500',
            rawPrice: 500,
            currencyCode: 'JPY',
          ),
      ],
      notFoundIDs: const [],
    );
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    callLog.add('buy(${purchaseParam.productDetails.id})');
    onBuy?.call(purchaseParam);
    return buyStarts;
  }

  @override
  Future<bool> buyConsumable({
    required PurchaseParam purchaseParam,
    bool autoConsume = true,
  }) async {
    callLog.add('buy(${purchaseParam.productDetails.id})');
    onBuy?.call(purchaseParam);
    return buyStarts;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    callLog.add('completePurchase(${purchase.productID})');
    final error = completePurchaseError;
    if (error != null) throw error;
  }

  @override
  T getPlatformAddition<T extends InAppPurchasePlatformAddition?>() =>
      addition as T;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('$invocation');
}

/// Extends the real client (composition, storage, preloaded-snapshot updates
/// all stay real) but records the money-relevant calls and stubs out the two
/// network methods.
class _RecordingBillingClient extends OcrBillingClient {
  _RecordingBillingClient({
    required this.callLog,
    required OcrBillingStatusStorage storage,
    required String? Function() readUid,
  }) : super(
         statusStorage: storage,
         readCurrentUid: readUid,
         ensureFirebaseApp: () async {},
       );

  final List<String> callLog;
  Object? verifyError;
  Object? refreshError;
  Object? setPlayEntitlementError;

  @override
  Future<void> setPlayEntitlement(bool owned) async {
    callLog.add('setPlayEntitlement($owned)');
    final error = setPlayEntitlementError;
    if (error != null) throw error;
    await super.setPlayEntitlement(owned);
  }

  @override
  Future<PurchaseGrantResult> verifyAndroidPurchase({
    required String productId,
    required String purchaseToken,
    String? orderId,
    bool isRestore = false,
  }) async {
    callLog.add('verify($productId, isRestore: $isRestore)');
    final error = verifyError;
    if (error != null) throw error;
    return PurchaseGrantResult(
      ocrUnlocked: true,
      creditBalance: 0,
      grantedCredits: ocrCreditProductIds.contains(productId) ? 500 : 0,
    );
  }

  @override
  Future<OcrBillingStatus?> refreshStatusIfAuthenticated({
    bool forceRefresh = false,
  }) async {
    final error = refreshError;
    if (error != null) throw error;
    return null;
  }
}

class _Harness {
  _Harness() : storage = _FakeStatusStorage() {
    iap = _FakeInAppPurchase(callLog);
    billing = _RecordingBillingClient(
      callLog: callLog,
      storage: storage,
      readUid: () => uid,
    );
    service = OcrStoreService.forTesting(
      inAppPurchase: iap,
      billingClient: billing,
    );
  }

  String? uid;
  final List<String> callLog = [];
  final _FakeStatusStorage storage;
  late final _FakeInAppPurchase iap;
  late final _RecordingBillingClient billing;
  late final OcrStoreService service;

  bool get hasEntitlement => storage.values[_playEntitlementKey] == '1';

  Iterable<String> get verifyCalls =>
      callLog.where((c) => c.startsWith('verify('));

  Iterable<String> get acknowledgeCalls =>
      callLog.where((c) => c.startsWith('completePurchase('));

  /// Starts a live purchase and delivers [update] through the purchase
  /// stream, the way Google Play does after the payment sheet closes.
  Future<PurchaseGrantResult> buyAndDeliver(
    String productId,
    PurchaseDetails update,
  ) {
    iap.onBuy = (_) => iap.purchaseUpdates.add([update]);
    return service.purchaseProduct(productId);
  }

  /// Makes the owned-purchases query report exactly [purchases].
  void playOwns(List<GooglePlayPurchaseDetails> purchases) {
    iap.addition.onQueryPastPurchases = () =>
        QueryPurchaseDetailsResponse(pastPurchases: purchases);
  }

  void playQueryFails() {
    iap.addition.onQueryPastPurchases = () => QueryPurchaseDetailsResponse(
      pastPurchases: const [],
      error: IAPError(
        source: 'google_play',
        code: 'query_failed',
        message: 'boom',
      ),
    );
  }

  Future<void> dispose() async {
    await service.dispose();
    await iap.purchaseUpdates.close();
    billing.dispose();
  }
}

void main() {
  group('isOwnedPlayPurchase', () {
    test('true for a Play purchase in the PURCHASED state', () {
      final details = _purchase(
        productId: proUnlockProductId,
        purchaseState: PurchaseStateWrapper.purchased,
      );
      expect(isOwnedPlayPurchase(details), isTrue);
    });

    test('false for a pending purchase even when the plugin reports it as '
        'restored', () {
      // The plugin's restore path rewrites status to `restored` for every
      // past purchase, including pending slow payments. Granting one would
      // hand out Pro before the money arrives.
      final details = _purchase(
        productId: proUnlockProductId,
        purchaseState: PurchaseStateWrapper.pending,
        status: PurchaseStatus.restored,
      );
      expect(isOwnedPlayPurchase(details), isFalse);
    });
  });

  group('proOwnershipFrom', () {
    test('null when the owned-purchases query failed', () {
      final response = QueryPurchaseDetailsResponse(
        pastPurchases: const [],
        error: IAPError(
          source: 'google_play',
          code: 'query_failed',
          message: 'boom',
        ),
      );
      expect(proOwnershipFrom(response), isNull);
    });

    test('false on a successful query that does not contain the pro SKU', () {
      final response = QueryPurchaseDetailsResponse(
        pastPurchases: [
          _purchase(
            productId: ocrCredit500ProductId,
            purchaseState: PurchaseStateWrapper.purchased,
          ),
        ],
      );
      expect(proOwnershipFrom(response), isFalse);
    });

    test('true when the pro SKU is owned', () {
      final response = QueryPurchaseDetailsResponse(
        pastPurchases: [
          _purchase(
            productId: proUnlockProductId,
            purchaseState: PurchaseStateWrapper.purchased,
          ),
        ],
      );
      expect(proOwnershipFrom(response), isTrue);
    });

    test('false when the pro SKU is present but still pending', () {
      final response = QueryPurchaseDetailsResponse(
        pastPurchases: [
          _purchase(
            productId: proUnlockProductId,
            purchaseState: PurchaseStateWrapper.pending,
            status: PurchaseStatus.restored,
          ),
        ],
      );
      expect(proOwnershipFrom(response), isFalse);
    });
  });

  group('OcrStoreService orchestration', () {
    late _Harness h;

    setUp(() {
      h = _Harness();
    });

    tearDown(() async {
      await h.dispose();
      PreloadedProEntitlement.setInitialSnapshot(null);
    });

    group('initialize', () {
      test('a billing channel error means unavailable, not a crash', () async {
        h.iap.isAvailableError = PlatformException(code: 'channel-error');

        await h.service.initialize();

        expect(h.service.isStoreAvailable, isFalse);

        // The startup warmup must also stay a no-op instead of surfacing the
        // channel error (MEKURU-18).
        await h.service.syncOwnedPurchases();
        expect(h.iap.addition.queryPastPurchasesCalls, 0);
      });

      test('concurrent initialize calls share a single probe', () async {
        await Future.wait([h.service.initialize(), h.service.initialize()]);

        expect(h.iap.isAvailableCalls, 1);
      });

      test(
        'an unavailable store is re-probed on the next initialize',
        () async {
          h.iap.available = false;
          await h.service.initialize();
          expect(h.service.isStoreAvailable, isFalse);

          h.iap.available = true;
          await h.service.initialize();
          expect(h.service.isStoreAvailable, isTrue);
          expect(h.iap.isAvailableCalls, 2);
        },
      );
    });

    group('purchaseProduct (pro unlock)', () {
      test(
        'grants, then acknowledges, then verifies for a signed-in buyer',
        () async {
          h.uid = 'user-1';

          final result = await h.buyAndDeliver(
            proUnlockProductId,
            _ownedProPurchase(),
          );

          expect(result.ocrUnlocked, isTrue);
          expect(h.hasEntitlement, isTrue);
          // The order is structural: nothing fallible may precede the
          // acknowledge, and the server verify always comes last.
          expect(
            h.callLog,
            containsAllInOrder([
              'buy($proUnlockProductId)',
              'setPlayEntitlement(true)',
              'completePurchase($proUnlockProductId)',
              'verify($proUnlockProductId, isRestore: false)',
            ]),
          );
        },
      );

      test('grants without any server call when nobody is signed in', () async {
        final result = await h.buyAndDeliver(
          proUnlockProductId,
          _ownedProPurchase(),
        );

        expect(result.ocrUnlocked, isTrue);
        expect(h.hasEntitlement, isTrue);
        expect(h.verifyCalls, isEmpty);
      });

      test(
        'a failed acknowledge does not fail the purchase — the unlock is '
        'already durable and the next owned-purchases sync retries',
        () async {
          h.iap.completePurchaseError = PlatformException(code: 'boom');

          final result = await h.buyAndDeliver(
            proUnlockProductId,
            _ownedProPurchase(),
          );

          expect(result.ocrUnlocked, isTrue);
          expect(h.hasEntitlement, isTrue);
        },
      );

      test('an unexpected delivery failure surfaces to the buyer instead of '
          'hanging the purchase', () async {
        // Arm the failure only after the pre-purchase sync so it hits the
        // purchase-stream delivery path.
        h.iap.onBuy = (_) {
          h.billing.setPlayEntitlementError = StateError('storage exploded');
          h.iap.purchaseUpdates.add([_ownedProPurchase()]);
        };

        await expectLater(
          h.service.purchaseProduct(proUnlockProductId),
          throwsA(isA<OcrBillingException>()),
        );
      });

      test('short-circuits without a payment sheet when the Play account '
          'already owns pro', () async {
        // Pre-purchase sync self-heals the entitlement from Play ownership.
        h.playOwns([_ownedProPurchase(pendingComplete: false)]);

        final result = await h.service.purchaseProduct(proUnlockProductId);

        expect(result.ocrUnlocked, isTrue);
        expect(h.hasEntitlement, isTrue);
        expect(h.callLog.where((c) => c.startsWith('buy(')), isEmpty);
      });

      test('a pending slow payment neither grants nor acknowledges', () async {
        final pending = _purchase(
          productId: proUnlockProductId,
          purchaseState: PurchaseStateWrapper.pending,
          status: PurchaseStatus.pending,
        );

        await expectLater(
          h.buyAndDeliver(proUnlockProductId, pending),
          throwsA(
            isA<OcrBillingException>().having(
              (e) => e.code,
              'code',
              'purchase_pending',
            ),
          ),
        );
        expect(h.hasEntitlement, isFalse);
        expect(h.acknowledgeCalls, isEmpty);
      });

      test(
        'a cancelled purchase is completed for cleanup but never granted',
        () async {
          final cancelled = _purchase(
            productId: proUnlockProductId,
            purchaseState: PurchaseStateWrapper.unspecified_state,
            status: PurchaseStatus.canceled,
            pendingComplete: true,
          );

          await expectLater(
            h.buyAndDeliver(proUnlockProductId, cancelled),
            throwsA(
              isA<OcrBillingException>().having(
                (e) => e.code,
                'code',
                'purchase_cancelled',
              ),
            ),
          );
          expect(h.hasEntitlement, isFalse);
          expect(h.acknowledgeCalls, isNotEmpty);
          expect(h.callLog, isNot(contains('setPlayEntitlement(true)')));
        },
      );

      test(
        'a declined payment surfaces payment_declined and never grants',
        () async {
          final declined = _purchase(
            productId: proUnlockProductId,
            purchaseState: PurchaseStateWrapper.unspecified_state,
            status: PurchaseStatus.error,
            pendingComplete: true,
          );

          await expectLater(
            h.buyAndDeliver(proUnlockProductId, declined),
            throwsA(
              isA<OcrBillingException>().having(
                (e) => e.code,
                'code',
                'payment_declined',
              ),
            ),
          );
          expect(h.hasEntitlement, isFalse);
        },
      );

      test('surfaces purchase_not_started when Play refuses to open the '
          'sheet', () async {
        h.iap.buyStarts = false;

        await expectLater(
          h.service.purchaseProduct(proUnlockProductId),
          throwsA(
            isA<OcrBillingException>().having(
              (e) => e.code,
              'code',
              'purchase_not_started',
            ),
          ),
        );
      });

      test('aborts before the payment sheet when the pre-purchase ownership '
          'query fails', () async {
        h.playQueryFails();

        await expectLater(
          h.service.purchaseProduct(proUnlockProductId),
          throwsA(
            isA<OcrBillingException>().having(
              (e) => e.code,
              'code',
              'restore_query_failed',
            ),
          ),
        );
        expect(h.callLog.where((c) => c.startsWith('buy(')), isEmpty);
      });
    });

    group('restorePurchases', () {
      test('unlocks from Play ownership alone with nobody signed in', () async {
        h.playOwns([_ownedProPurchase(pendingComplete: false)]);

        final status = await h.service.restorePurchases();

        expect(status.ocrUnlocked, isTrue);
        expect(h.hasEntitlement, isTrue);
        expect(h.verifyCalls, isEmpty);
      });

      test('verifies with isRestore for a signed-in user', () async {
        h.uid = 'user-1';
        h.playOwns([_ownedProPurchase(pendingComplete: false)]);

        final status = await h.service.restorePurchases();

        expect(status.ocrUnlocked, isTrue);
        expect(
          h.callLog,
          contains('verify($proUnlockProductId, isRestore: true)'),
        );
      });

      test('a failed server verify is non-fatal and cannot block the '
          'acknowledge that already happened', () async {
        h.uid = 'user-1';
        h.billing.verifyError = const OcrBillingException(500, 'server down');
        h.playOwns([_ownedProPurchase()]);

        final status = await h.service.restorePurchases();

        expect(status.ocrUnlocked, isTrue);
        expect(h.hasEntitlement, isTrue);
        expect(
          h.callLog,
          containsAllInOrder([
            'completePurchase($proUnlockProductId)',
            'verify($proUnlockProductId, isRestore: true)',
          ]),
        );
      });

      test('a failed server status refresh is non-fatal', () async {
        h.billing.refreshError = const OcrBillingException(500, 'server down');
        h.playOwns([_ownedProPurchase(pendingComplete: false)]);

        final status = await h.service.restorePurchases();

        expect(status.ocrUnlocked, isTrue);
      });

      test('reports locked when the account owns nothing', () async {
        final status = await h.service.restorePurchases();

        expect(status.ocrUnlocked, isFalse);
        expect(h.hasEntitlement, isFalse);
      });

      test('converges a refund: restoring on a refunded install relocks and '
          'clears the entitlement', () async {
        h.storage.values[_playEntitlementKey] = '1';

        final status = await h.service.restorePurchases();

        expect(status.ocrUnlocked, isFalse);
        expect(h.hasEntitlement, isFalse);
      });

      test('surfaces restore_query_failed and keeps the entitlement when the '
          'owned-purchases query fails', () async {
        h.storage.values[_playEntitlementKey] = '1';
        h.playQueryFails();

        await expectLater(
          h.service.restorePurchases(),
          throwsA(
            isA<OcrBillingException>().having(
              (e) => e.code,
              'code',
              'restore_query_failed',
            ),
          ),
        );
        // A failed query must never be treated as a refund.
        expect(h.hasEntitlement, isTrue);
      });
    });

    group('syncOwnedPurchases (startup warmup)', () {
      test('grants the entitlement for a legacy buyer without re-verifying '
          'on the server', () async {
        h.uid = 'user-1';
        h.playOwns([_ownedProPurchase(pendingComplete: false)]);

        await h.service.syncOwnedPurchases();

        expect(h.hasEntitlement, isTrue);
        // The passive startup sync must never re-POST a verify each launch.
        expect(h.verifyCalls, isEmpty);
      });

      test('converges a refund: a successful query without the SKU clears '
          'the entitlement', () async {
        h.storage.values[_playEntitlementKey] = '1';

        await h.service.syncOwnedPurchases();

        expect(h.hasEntitlement, isFalse);
      });

      test('a failed query leaves the stored entitlement untouched', () async {
        h.storage.values[_playEntitlementKey] = '1';
        h.playQueryFails();

        await h.service.syncOwnedPurchases();

        expect(h.hasEntitlement, isTrue);
      });

      test('a pending slow payment in the owned list neither grants nor '
          'acknowledges', () async {
        // The plugin rewrites pending past purchases to `restored`; the raw
        // Play purchaseState is the only trustworthy gate.
        h.playOwns([
          _purchase(
            productId: proUnlockProductId,
            purchaseState: PurchaseStateWrapper.pending,
            status: PurchaseStatus.restored,
            pendingComplete: true,
          ),
        ]);

        await h.service.syncOwnedPurchases();

        expect(h.hasEntitlement, isFalse);
        expect(h.acknowledgeCalls, isEmpty);
      });

      test('one failing delivery cannot starve the others', () async {
        // The credit purchase throws during its server verify; the pro
        // purchase that Play happens to list after it must still be granted.
        h.uid = 'user-1';
        h.billing.verifyError = const OcrBillingException(500, 'server down');
        h.playOwns([
          _creditPurchase(),
          _ownedProPurchase(pendingComplete: false),
        ]);

        await h.service.syncOwnedPurchases();

        expect(h.hasEntitlement, isTrue);
      });
    });

    group('credit purchases (dormant flow)', () {
      test('are never acknowledged without a signed-in user', () async {
        // Acknowledging a consumable without the server grant eats it.
        h.playOwns([_creditPurchase()]);

        await h.service.syncOwnedPurchases();

        expect(h.verifyCalls, isEmpty);
        expect(h.acknowledgeCalls, isEmpty);
      });

      test(
        'keep verify-then-acknowledge order for a signed-in buyer',
        () async {
          h.uid = 'user-1';

          final result = await h.buyAndDeliver(
            ocrCredit500ProductId,
            _creditPurchase(),
          );

          expect(result.grantedCredits, 500);
          expect(
            h.callLog,
            containsAllInOrder([
              'verify($ocrCredit500ProductId, isRestore: false)',
              'completePurchase($ocrCredit500ProductId)',
            ]),
          );
        },
      );

      test('a failed verify never acknowledges the consumable', () async {
        h.uid = 'user-1';
        h.billing.verifyError = const OcrBillingException(500, 'server down');

        await expectLater(
          h.buyAndDeliver(ocrCredit500ProductId, _creditPurchase()),
          throwsA(isA<OcrBillingException>()),
        );
        expect(h.acknowledgeCalls, isEmpty);
      });
    });

    group('purchase stream hygiene', () {
      test('ignores SKUs that are not ours', () async {
        await h.service.initialize();

        h.iap.purchaseUpdates.add([
          _purchase(
            productId: 'some_other_app_sku',
            purchaseState: PurchaseStateWrapper.purchased,
            pendingComplete: true,
          ),
        ]);
        await pumpEventQueue();

        expect(h.acknowledgeCalls, isEmpty);
        expect(h.hasEntitlement, isFalse);
      });

      test('a purchase that lands after the UI stopped waiting reaches '
          'onLateDelivery', () async {
        PurchaseGrantResult? late_;
        h.service.onLateDelivery = (result) => late_ = result;
        await h.service.initialize();

        h.iap.purchaseUpdates.add([_ownedProPurchase()]);
        await pumpEventQueue();

        expect(late_?.ocrUnlocked, isTrue);
        expect(h.hasEntitlement, isTrue);
      });
    });
  });
}
