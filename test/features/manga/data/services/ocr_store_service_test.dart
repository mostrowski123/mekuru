import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:mekuru/features/manga/data/services/ocr_store_service.dart';

GooglePlayPurchaseDetails _purchase({
  required String productId,
  required PurchaseStateWrapper purchaseState,
  PurchaseStatus status = PurchaseStatus.purchased,
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
  );
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
}
