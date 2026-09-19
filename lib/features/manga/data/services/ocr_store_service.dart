import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';

import 'ocr_billing_client.dart';

const proUnlockProductId = 'pro_unlock_v1';
const ocrCredit500ProductId = 'ocr_pages_500';
const ocrCredit1500ProductId = 'ocr_pages_1500';
const ocrCredit4000ProductId = 'ocr_pages_4000';

const Set<String> proUnlockProductIds = {proUnlockProductId};
const Set<String> ocrCreditProductIds = {
  ocrCredit500ProductId,
  ocrCredit1500ProductId,
  ocrCredit4000ProductId,
};
const Set<String> ocrAllProductIds = {
  proUnlockProductId,
  ocrCredit500ProductId,
  ocrCredit1500ProductId,
  ocrCredit4000ProductId,
};
const Set<String> ocrVisibleProductIds = proUnlockProductIds;

/// True when Google Play reports this purchase as actually paid.
///
/// [PurchaseDetails.status] is not trustworthy for this: the plugin's restore
/// path rewrites it to `restored` even for pending slow-payment purchases.
/// Granting or acknowledging a pending purchase would hand out Pro (and eat
/// the purchase) before the money arrives, so gate on the raw Play state.
bool isOwnedPlayPurchase(PurchaseDetails details) {
  return details is GooglePlayPurchaseDetails &&
      details.billingClientPurchase.purchaseState ==
          PurchaseStateWrapper.purchased;
}

/// Whether the Play account owns the Pro unlock according to an
/// owned-purchases query. Returns null when the query failed — callers must
/// leave the stored entitlement untouched in that case, never clear it.
bool? proOwnershipFrom(QueryPurchaseDetailsResponse response) {
  if (response.error != null) {
    return null;
  }
  return response.pastPurchases.any(
    (details) =>
        details.productID == proUnlockProductId && isOwnedPlayPurchase(details),
  );
}

/// True when the App Store reports this purchase as paid and not refunded.
///
/// The status is not enough on iOS: the plugin forwards every verified
/// StoreKit transaction as `purchased`, including the update StoreKit sends
/// when a purchase is refunded or revoked, so trusting it would hand Pro
/// back on a refund.
bool isOwnedAppStorePurchase(PurchaseDetails details) {
  if (details is! SK2PurchaseDetails) return false;
  if (details.status != PurchaseStatus.purchased &&
      details.status != PurchaseStatus.restored) {
    return false;
  }
  return !isRevokedAppStoreTransaction(
    details.verificationData.localVerificationData,
  );
}

/// Whether a StoreKit 2 transaction's JSON payload carries a
/// `revocationDate` (refund, or Family Sharing access withdrawn). JSON that
/// cannot be read counts as not revoked: it only reaches here for a
/// transaction StoreKit already verified, and locking out a payer is worse
/// than a refund staying unlocked until the next ownership sync.
bool isRevokedAppStoreTransaction(String? transactionJson) {
  if (transactionJson == null || transactionJson.isEmpty) return false;
  try {
    final decoded = jsonDecode(transactionJson);
    return decoded is Map && decoded['revocationDate'] != null;
  } on FormatException {
    return false;
  }
}

/// Whether the App Store account owns the Pro unlock: some Pro transaction
/// that has not been refunded or revoked.
bool ownsProInAppStore(Iterable<SK2Transaction> transactions) {
  return transactions.any(
    (t) =>
        t.productId == proUnlockProductId &&
        !isRevokedAppStoreTransaction(t.jsonRepresentation),
  );
}

// ponytail: DI is test-only (forTesting) — app code always goes through the
// plain singleton on InAppPurchase.instance.
class OcrStoreService {
  OcrStoreService._()
    : _inAppPurchase = InAppPurchase.instance,
      _billingClient = OcrBillingClient(),
      _appStoreTransactions = SK2Transaction.transactions,
      _appStoreSync = AppStore().sync;

  /// The purchase orchestration (grant→acknowledge→verify order, refund
  /// convergence, waiter semantics) is only reachable with fakes behind
  /// these seams.
  @visibleForTesting
  OcrStoreService.forTesting({
    required InAppPurchase inAppPurchase,
    required OcrBillingClient billingClient,
    Future<List<SK2Transaction>> Function()? appStoreTransactions,
    Future<void> Function()? appStoreSync,
  }) : _inAppPurchase = inAppPurchase,
       _billingClient = billingClient,
       _appStoreTransactions = appStoreTransactions ?? (() async => const []),
       _appStoreSync = appStoreSync ?? (() async {});

  static final OcrStoreService instance = OcrStoreService._();

  final InAppPurchase _inAppPurchase;
  final OcrBillingClient _billingClient;

  /// StoreKit 2's `Transaction.all` and `AppStore.sync()`. The plugin only
  /// exposes them as statics, so they are held here to stay fakeable.
  final Future<List<SK2Transaction>> Function() _appStoreTransactions;
  final Future<void> Function() _appStoreSync;

  // defaultTargetPlatform (not dart:io Platform) so host unit tests, which
  // flutter_test runs as android, exercise the real code paths.
  static bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;
  static bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;
  static bool get _hasStore => _isAndroid || _isIos;
  static String get _storeName => _isIos ? 'the App Store' : 'Google Play';
  final Map<String, ProductDetails> _productCache = {};
  final Map<String, List<Completer<PurchaseGrantResult>>> _pendingWaiters = {};

  /// Called when a purchase is verified successfully but no waiter was active
  /// (e.g. a pending payment that completed after the UI dismissed the
  /// spinner).  The UI can listen to this to refresh Pro status.
  void Function(PurchaseGrantResult result)? onLateDelivery;

  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  Future<void>? _initializing;
  bool _storeAvailable = false;

  /// Whether Google Play billing responded as available on the most recent
  /// [initialize] probe. The Pro screen keys its buttons off this.
  bool get isStoreAvailable => _storeAvailable;

  void _log(String message, [Map<String, Object?> details = const {}]) {
    final suffix = details.isEmpty ? '' : ' $details';
    debugPrint('[OcrStoreService] $message$suffix');
  }

  Future<void> initialize() {
    if (_storeAvailable) return Future.value();
    // Re-probing after an unavailable result is allowed, but concurrent
    // callers must share one attempt so the stream is subscribed only once.
    return _initializing ??= _doInitialize().whenComplete(
      () => _initializing = null,
    );
  }

  Future<void> _doInitialize() async {
    if (!_hasStore) return;

    bool isAvailable;
    try {
      isAvailable = await _inAppPurchase.isAvailable();
    } on PlatformException catch (e) {
      // Billing being unreachable (emulators, non-Play installs) surfaces as
      // a pigeon channel error; treat it as unavailable rather than letting
      // the startup warmup report an app failure (MEKURU-18).
      logUsage('billing.unavailable', attrs: {'code': e.code});
      isAvailable = false;
    }
    _log('initialize', {'isAvailable': isAvailable});
    _storeAvailable = isAvailable;
    if (!isAvailable) {
      return;
    }

    _purchaseSubscription = _inAppPurchase.purchaseStream.listen(
      (detailsList) {
        _log('purchaseStream event', {'count': detailsList.length});
        unawaited(_handlePurchaseUpdates(detailsList));
      },
      onError: (Object error, StackTrace stackTrace) {
        _log('purchaseStream error', {'error': error.toString()});
        _completeAllPendingWithError(
          OcrBillingException(
            500,
            'Failed to observe $_storeName purchase updates: $error',
            code: 'purchase_stream_error',
          ),
        );
      },
    );
  }

  Future<Map<String, ProductDetails>> queryProducts(
    Set<String> productIds,
  ) async {
    await initialize();
    if (!_hasStore) {
      throw const OcrBillingException(
        422,
        'Purchases are not available on this platform.',
        code: 'platform_unsupported',
      );
    }

    final response = await _inAppPurchase.queryProductDetails(productIds);
    _log('queryProducts', {
      'requested': productIds.join(','),
      'found': response.productDetails.map((p) => p.id).join(','),
      'notFound': response.notFoundIDs.join(','),
      'error': response.error?.message,
    });
    if (response.error != null) {
      throw OcrBillingException(
        502,
        response.error!.message,
        code: 'store_query_failed',
      );
    }

    for (final product in response.productDetails) {
      _productCache[product.id] = product;
    }

    final missing = productIds.where((id) => !_productCache.containsKey(id));
    if (missing.isNotEmpty) {
      throw OcrBillingException(
        422,
        'Missing $_storeName products: ${missing.join(', ')}',
        code: 'store_product_missing',
      );
    }

    return {for (final id in productIds) id: _productCache[id]!};
  }

  Future<PurchaseGrantResult> purchaseProduct(String productId) async {
    await initialize();
    if (!_hasStore) {
      throw const OcrBillingException(
        422,
        'Purchases are not available on this platform.',
        code: 'platform_unsupported',
      );
    }

    await _syncOwnedPurchases(reason: 'pre_purchase:$productId');
    if (productId == proUnlockProductId) {
      // The sync above just refreshed the local Play entitlement, so this
      // also self-heals installs stuck with an unverified old purchase.
      final localStatus = await _billingClient.readLastKnownStatus();
      if (localStatus?.ocrUnlocked ?? false) {
        _log('purchase short-circuited by existing unlock', {
          'productId': productId,
          'creditBalance': localStatus!.creditBalance,
        });
        return PurchaseGrantResult(
          ocrUnlocked: true,
          creditBalance: localStatus.creditBalance,
          grantedCredits: 0,
        );
      }
    }

    final products = await queryProducts({productId});
    final productDetails = products[productId]!;
    final purchaseParam = PurchaseParam(productDetails: productDetails);
    final waiter = Completer<PurchaseGrantResult>();
    _pendingWaiters.putIfAbsent(productId, () => []).add(waiter);

    bool started = false;
    try {
      _log('starting purchase', {'productId': productId});
      if (ocrCreditProductIds.contains(productId)) {
        started = await _inAppPurchase.buyConsumable(
          purchaseParam: purchaseParam,
          autoConsume: false,
        );
      } else {
        started = await _inAppPurchase.buyNonConsumable(
          purchaseParam: purchaseParam,
        );
      }

      if (!started) {
        _log('purchase did not start', {'productId': productId});
        throw const OcrBillingException(
          409,
          'The purchase did not start. Please try again.',
          code: 'purchase_not_started',
        );
      }

      return await waiter.future.timeout(
        const Duration(minutes: 3),
        onTimeout: () {
          throw OcrBillingException(
            408,
            'Timed out waiting for $_storeName to finish the purchase.',
            code: 'purchase_timeout',
          );
        },
      );
    } catch (e) {
      _log('purchase threw before completion', {
        'productId': productId,
        'error': e.toString(),
      });
      _removeWaiter(productId, waiter);
      rethrow;
    }
  }

  Future<OcrBillingStatus> restorePurchases() async {
    await initialize();
    if (_hasStore) {
      _log('restorePurchases start');
      await _syncOwnedPurchases(reason: 'restore', isRestore: true);
    }
    // Best-effort server refresh for signed-in users (null no-op otherwise);
    // the composed local read below already reflects both it and the sync.
    try {
      await _billingClient.refreshStatusIfAuthenticated(forceRefresh: true);
    } catch (e) {
      _log('restore server refresh failed', {'error': e.toString()});
    }
    final status =
        await _billingClient.readLastKnownStatus() ??
        const OcrBillingStatus(ocrUnlocked: false, creditBalance: 0);
    _log('restorePurchases complete', {
      'ocrUnlocked': status.ocrUnlocked,
      'creditBalance': status.creditBalance,
    });
    return status;
  }

  /// Fire-and-forget convergence of the local Play entitlement with the
  /// owned-purchases list (startup warmup). Never throws; a failed query
  /// leaves the stored entitlement untouched.
  Future<void> syncOwnedPurchases() async {
    try {
      await initialize();
      if (!_storeAvailable) return;
      await _syncOwnedPurchases(reason: 'startup');
    } catch (e) {
      _log('owned purchase sync failed', {'error': e.toString()});
    }
  }

  Future<void> _handlePurchaseUpdates(List<PurchaseDetails> detailsList) async {
    for (final details in detailsList) {
      _log('processing purchase update', {
        'productId': details.productID,
        'status': details.status.name,
        'pendingCompletePurchase': details.pendingCompletePurchase,
        'purchaseId': details.purchaseID,
      });

      if (!ocrAllProductIds.contains(details.productID)) {
        continue;
      }

      if (details.status == PurchaseStatus.pending) {
        _log('purchase pending – payment is being processed', {
          'productId': details.productID,
        });
        _completeWaiterWithError(
          details.productID,
          const OcrBillingException(
            202,
            'Your payment is being processed. '
            'You will be unlocked automatically once it is confirmed.',
            code: 'purchase_pending',
          ),
        );
        continue;
      }

      if (details.status == PurchaseStatus.error) {
        _completeWaiterWithError(
          details.productID,
          OcrBillingException(
            502,
            details.error?.message ??
                'Your payment could not be processed. '
                    'Please try a different payment method.',
            code: 'payment_declined',
          ),
        );
        await _completeIfPending(details, 'stream_error');
        continue;
      }

      if (details.status == PurchaseStatus.canceled) {
        _completeWaiterWithError(
          details.productID,
          const OcrBillingException(
            409,
            'The purchase was cancelled.',
            code: 'purchase_cancelled',
          ),
        );
        await _completeIfPending(details, 'stream_cancelled');
        continue;
      }

      if (details.status == PurchaseStatus.purchased ||
          details.status == PurchaseStatus.restored) {
        try {
          await _deliverPurchase(
            details,
            source: details.status == PurchaseStatus.restored
                ? 'purchase_stream_restored'
                : 'purchase_stream_purchased',
            completeWaiterOnSuccess: true,
          );
        } catch (e) {
          // Same invariant as the owned-purchases loop: one bad item must
          // not starve the others — and a live buyer must get an answer,
          // never a hanging spinner.
          _log('purchase delivery failed', {
            'productId': details.productID,
            'error': e.toString(),
          });
          _completeWaiterWithError(
            details.productID,
            e is OcrBillingException
                ? e
                : OcrBillingException(
                    500,
                    'Failed to deliver the purchase: $e',
                    code: 'purchase_delivery_failed',
                  ),
          );
        }
      }
    }
  }

  Future<void> _syncOwnedPurchases({
    required String reason,
    bool isRestore = false,
  }) async {
    if (_isIos) {
      return _syncOwnedAppStorePurchases(reason: reason, isRestore: isRestore);
    }
    if (!_isAndroid) return;

    final addition = _inAppPurchase
        .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
    final response = await addition.queryPastPurchases();
    _log('queryPastPurchases', {
      'reason': reason,
      'count': response.pastPurchases.length,
      'error': response.error?.message,
    });

    if (response.error != null) {
      throw OcrBillingException(
        502,
        response.error!.message,
        code: 'restore_query_failed',
      );
    }

    for (final details in response.pastPurchases) {
      if (!ocrAllProductIds.contains(details.productID)) {
        continue;
      }
      try {
        await _deliverPurchase(
          details,
          source: 'query_past:$reason',
          completeWaiterOnSuccess: false,
          isRestoreOverride: isRestore ? true : null,
        );
      } catch (e) {
        // One bad item must not starve the others (Play returns purchases in
        // unspecified order).
        _log('owned purchase delivery failed', {
          'productId': details.productID,
          'error': e.toString(),
        });
      }
    }

    final ownsPro = proOwnershipFrom(response);
    if (ownsPro != null) {
      await _billingClient.setPlayEntitlement(ownsPro);
    }
  }

  /// iOS counterpart of the owned-purchases query. Nothing is delivered from
  /// here: StoreKit replays unfinished transactions through the purchase
  /// stream at launch, and that path grants and finishes them.
  ///
  /// ponytail: `Transaction.all` answers from StoreKit's local cache and
  /// cannot report "I could not reach the App Store". A reinstall whose first
  /// launch is offline therefore reads as not owned and clears a flag the
  /// Keychain kept; the next online sync grants it again. Revisit if payers
  /// report losing Pro offline.
  Future<void> _syncOwnedAppStorePurchases({
    required String reason,
    required bool isRestore,
  }) async {
    if (isRestore) {
      // Only on an explicit restore: this can show an App Store sign-in
      // prompt. Cancelling it is not an error worth surfacing.
      try {
        await _appStoreSync();
      } catch (e) {
        _log('AppStore.sync failed (non-fatal)', {'error': e.toString()});
      }
    }

    final List<SK2Transaction> transactions;
    try {
      transactions = await _appStoreTransactions();
    } on PlatformException catch (e) {
      throw OcrBillingException(
        502,
        e.message ?? 'Could not read your App Store purchases.',
        code: 'restore_query_failed',
      );
    }
    final ownsPro = ownsProInAppStore(transactions);
    _log('appStoreTransactions', {
      'reason': reason,
      'count': transactions.length,
      'ownsPro': ownsPro,
    });
    await _billingClient.setPlayEntitlement(ownsPro);
  }

  Future<void> _deliverPurchase(
    PurchaseDetails details, {
    required String source,
    required bool completeWaiterOnSuccess,
    bool? isRestoreOverride,
  }) => details.productID == proUnlockProductId
      ? _deliverProUnlock(
          details,
          source: source,
          completeWaiterOnSuccess: completeWaiterOnSuccess,
          isRestoreOverride: isRestoreOverride,
        )
      : _deliverCreditPurchase(
          details,
          source: source,
          completeWaiterOnSuccess: completeWaiterOnSuccess,
          isRestoreOverride: isRestoreOverride,
        );

  Future<void> _completeIfPending(
    PurchaseDetails details,
    String source,
  ) async {
    if (!details.pendingCompletePurchase) return;
    _log('completing purchase', {
      'source': source,
      'productId': details.productID,
    });
    try {
      await _inAppPurchase.completePurchase(details);
    } catch (e) {
      // Never fatal: by this point the purchase outcome is already decided
      // (pro flag set / credits granted / waiter errored). Play redelivers
      // unacknowledged purchases on the next owned-purchases sync, so the
      // acknowledge retries then instead of failing the whole delivery.
      _log('completePurchase failed (will retry on next sync)', {
        'source': source,
        'productId': details.productID,
        'error': e.toString(),
      });
    }
  }

  /// The Pro unlock is granted from Play ownership alone — no account, no
  /// server round-trip. Order is structural, not conditional: grant, then
  /// acknowledge, then best-effort server bookkeeping last, so no failure
  /// can leave a paid purchase unacknowledged (Google auto-refunds those
  /// after ~3 days).
  Future<void> _deliverProUnlock(
    PurchaseDetails details, {
    required String source,
    required bool completeWaiterOnSuccess,
    bool? isRestoreOverride,
  }) async {
    if (details is SK2PurchaseDetails && !isOwnedAppStorePurchase(details)) {
      // A refund or revocation notice. Finish it so StoreKit stops replaying
      // it, and let the ownership query decide whether Pro goes away.
      _log('pro purchase revoked', {'source': source});
      await _completeIfPending(details, source);
      await syncOwnedPurchases();
      return;
    }
    if (!isOwnedPlayPurchase(details) && !isOwnedAppStorePurchase(details)) {
      // Pending slow payment: no grant, no acknowledge. The purchase stream
      // delivers it again once Play confirms the money arrived.
      _log('pro purchase not yet owned – skipping', {
        'source': source,
        'status': details.status.name,
      });
      return;
    }

    await _billingClient.setPlayEntitlement(true);
    await _completeIfPending(details, source);

    final cached = await _billingClient.readLastKnownStatus();
    if (completeWaiterOnSuccess) {
      _completeWaiter(
        details.productID,
        PurchaseGrantResult(
          ocrUnlocked: true,
          creditBalance: cached?.creditBalance ?? 0,
          grantedCredits: 0,
        ),
      );
    }

    // Keep the server ledger fresh for already-signed-in users (existing
    // buyers) — but only on live purchases and explicit restores, not the
    // passive startup sync, which would otherwise re-verify on every launch.
    // Failures are non-fatal: Play ownership is the ground truth here.
    // Android only: the backend has no App Store verification yet.
    final shouldVerify =
        _isAndroid &&
        _billingClient.hasAuthenticatedUser &&
        (completeWaiterOnSuccess || isRestoreOverride == true);
    if (shouldVerify) {
      try {
        await _billingClient.verifyAndroidPurchase(
          productId: details.productID,
          purchaseToken: _extractPurchaseToken(details),
          orderId: details.purchaseID,
          isRestore:
              isRestoreOverride ?? details.status == PurchaseStatus.restored,
        );
      } catch (e) {
        _log('server verify failed (non-fatal)', {
          'source': source,
          'error': e.toString(),
        });
      }
    }
  }

  /// Credit consumables (dormant — no purchase UI) keep the original
  /// verify-then-acknowledge order: acknowledging a consumable without the
  /// server grant would eat the purchase.
  Future<void> _deliverCreditPurchase(
    PurchaseDetails details, {
    required String source,
    required bool completeWaiterOnSuccess,
    bool? isRestoreOverride,
  }) async {
    if (!_billingClient.hasAuthenticatedUser) {
      _log('skipping credit purchase without signed-in user', {
        'source': source,
        'productId': details.productID,
      });
      return;
    }

    var verified = false;
    try {
      final purchaseToken = _extractPurchaseToken(details);
      _log('verifying purchase', {
        'source': source,
        'productId': details.productID,
        'purchaseTokenSuffix': purchaseToken.length <= 8
            ? purchaseToken
            : purchaseToken.substring(purchaseToken.length - 8),
        'purchaseId': details.purchaseID,
      });
      final result = await _billingClient.verifyAndroidPurchase(
        productId: details.productID,
        purchaseToken: purchaseToken,
        orderId: details.purchaseID,
        isRestore:
            isRestoreOverride ?? details.status == PurchaseStatus.restored,
      );
      verified = true;
      _log('verify success', {
        'source': source,
        'productId': details.productID,
        'ocrUnlocked': result.ocrUnlocked,
        'creditBalance': result.creditBalance,
        'grantedCredits': result.grantedCredits,
      });
      if (completeWaiterOnSuccess) {
        _completeWaiter(details.productID, result);
      }
    } catch (e) {
      final error = e is OcrBillingException
          ? e
          : OcrBillingException(
              500,
              'Failed to verify the purchase with the OCR server: $e',
              code: 'purchase_verify_failed',
            );
      _log('verify failed', {
        'source': source,
        'productId': details.productID,
        'statusCode': error.statusCode,
        'code': error.code,
        'message': error.message,
      });
      if (completeWaiterOnSuccess) {
        _completeWaiterWithError(details.productID, error);
      } else {
        rethrow;
      }
    } finally {
      if (verified) {
        await _completeIfPending(details, source);
      }
    }
  }

  String _extractPurchaseToken(PurchaseDetails details) {
    if (details is GooglePlayPurchaseDetails) {
      return details.billingClientPurchase.purchaseToken;
    }
    throw const OcrBillingException(
      422,
      'Could not read the Google Play purchase token.',
      code: 'purchase_token_missing',
    );
  }

  void _completeWaiter(String productId, PurchaseGrantResult result) {
    final queue = _pendingWaiters[productId];
    if (queue == null || queue.isEmpty) {
      _log('no waiter for verified purchase – invoking onLateDelivery', {
        'productId': productId,
      });
      onLateDelivery?.call(result);
      return;
    }
    final waiter = queue.removeAt(0);
    if (!waiter.isCompleted) {
      waiter.complete(result);
    }
    if (queue.isEmpty) {
      _pendingWaiters.remove(productId);
    }
  }

  void _completeWaiterWithError(String productId, OcrBillingException error) {
    final queue = _pendingWaiters[productId];
    if (queue == null || queue.isEmpty) {
      return;
    }
    final waiter = queue.removeAt(0);
    if (!waiter.isCompleted) {
      waiter.completeError(error);
    }
    if (queue.isEmpty) {
      _pendingWaiters.remove(productId);
    }
  }

  void _removeWaiter(String productId, Completer<PurchaseGrantResult> waiter) {
    final queue = _pendingWaiters[productId];
    if (queue == null) return;
    queue.remove(waiter);
    if (queue.isEmpty) {
      _pendingWaiters.remove(productId);
    }
  }

  void _completeAllPendingWithError(OcrBillingException error) {
    final keys = _pendingWaiters.keys.toList(growable: false);
    for (final key in keys) {
      final queue = _pendingWaiters.remove(key) ?? const [];
      for (final waiter in queue) {
        if (!waiter.isCompleted) {
          waiter.completeError(error);
        }
      }
    }
  }

  Future<void> dispose() async {
    await _purchaseSubscription?.cancel();
    _purchaseSubscription = null;
    _storeAvailable = false;
  }
}
