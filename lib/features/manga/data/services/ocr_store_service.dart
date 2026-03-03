import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

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

class OcrStoreService {
  OcrStoreService._();

  static final OcrStoreService instance = OcrStoreService._();

  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  final OcrBillingClient _billingClient = OcrBillingClient();
  final Map<String, ProductDetails> _productCache = {};
  final Map<String, List<Completer<PurchaseGrantResult>>> _pendingWaiters = {};

  /// Called when a purchase is verified successfully but no waiter was active
  /// (e.g. a pending payment that completed after the UI dismissed the
  /// spinner).  The UI can listen to this to refresh Pro status.
  void Function(PurchaseGrantResult result)? onLateDelivery;

  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  bool _isInitialized = false;

  void _log(String message, [Map<String, Object?> details = const {}]) {
    final suffix = details.isEmpty ? '' : ' $details';
    debugPrint('[OcrStoreService] $message$suffix');
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    if (!Platform.isAndroid) return;

    final isAvailable = await _inAppPurchase.isAvailable();
    _log('initialize', {'isAvailable': isAvailable});
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
            'Failed to observe Google Play purchase updates: $error',
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
    if (!Platform.isAndroid) {
      throw const OcrBillingException(
        422,
        'OCR purchases are only available on Android right now.',
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
        'Missing Google Play products: ${missing.join(', ')}',
        code: 'store_product_missing',
      );
    }

    return {for (final id in productIds) id: _productCache[id]!};
  }

  Future<PurchaseGrantResult> purchaseProduct(String productId) async {
    await initialize();
    if (!Platform.isAndroid) {
      throw const OcrBillingException(
        422,
        'OCR purchases are only available on Android right now.',
        code: 'platform_unsupported',
      );
    }

    await _syncOwnedPurchases(reason: 'pre_purchase:$productId');
    final statusAfterSync = await _billingClient.fetchStatus(
      forceRefresh: true,
    );
    if (productId == proUnlockProductId && statusAfterSync.ocrUnlocked) {
      _log('purchase short-circuited by existing unlock', {
        'productId': productId,
        'creditBalance': statusAfterSync.creditBalance,
      });
      return PurchaseGrantResult(
        ocrUnlocked: true,
        creditBalance: statusAfterSync.creditBalance,
        grantedCredits: 0,
      );
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

      return waiter.future.timeout(
        const Duration(minutes: 3),
        onTimeout: () {
          throw const OcrBillingException(
            408,
            'Timed out waiting for Google Play to finish the purchase.',
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
    if (Platform.isAndroid) {
      _log('restorePurchases start');
      await _inAppPurchase.restorePurchases();
      await Future<void>.delayed(const Duration(seconds: 2));
      await _syncOwnedPurchases(reason: 'restore', isRestore: true);
    }
    final status = await _billingClient.fetchStatus(forceRefresh: true);
    _log('restorePurchases complete', {
      'ocrUnlocked': status.ocrUnlocked,
      'creditBalance': status.creditBalance,
    });
    return status;
  }

  Future<void> _handlePurchaseUpdates(List<PurchaseDetails> detailsList) async {
    for (final details in detailsList) {
      _log('processing purchase update', {
        'productId': details.productID,
        'status': details.status.name,
        'pendingCompletePurchase': details.pendingCompletePurchase,
        'purchaseId': details.purchaseID,
      });

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
        if (details.pendingCompletePurchase) {
          await _inAppPurchase.completePurchase(details);
        }
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
        if (details.pendingCompletePurchase) {
          await _inAppPurchase.completePurchase(details);
        }
        continue;
      }

      if (details.status == PurchaseStatus.purchased ||
          details.status == PurchaseStatus.restored) {
        await _deliverPurchase(
          details,
          source: details.status == PurchaseStatus.restored
              ? 'purchase_stream_restored'
              : 'purchase_stream_purchased',
          completeWaiterOnSuccess: true,
        );
      }
    }
  }

  Future<void> _syncOwnedPurchases({
    required String reason,
    bool isRestore = false,
  }) async {
    if (!Platform.isAndroid) return;

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
      await _deliverPurchase(
        details,
        source: 'query_past:$reason',
        completeWaiterOnSuccess: false,
        isRestoreOverride: isRestore ? true : null,
      );
    }
  }

  Future<void> _deliverPurchase(
    PurchaseDetails details, {
    required String source,
    required bool completeWaiterOnSuccess,
    bool? isRestoreOverride,
  }) async {
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
      if (verified && details.pendingCompletePurchase) {
        _log('completing purchase', {
          'source': source,
          'productId': details.productID,
        });
        await _inAppPurchase.completePurchase(details);
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
    _isInitialized = false;
  }
}
