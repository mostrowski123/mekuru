import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:mekuru/features/manga/data/services/ocr_auth_secret_storage.dart';
import 'package:mekuru/features/settings/data/services/ocr_server_config.dart'
    as ocr_server_config;
import 'package:mekuru/features/settings/presentation/screens/settings_screen.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/services/ocr_account_link_service.dart';
import '../../data/services/ocr_billing_client.dart';
import '../../data/services/ocr_store_service.dart';

class OcrPreparationResult {
  final OcrJobReservation? reservation;

  const OcrPreparationResult({this.reservation});
}

class OcrPurchaseFlow {
  OcrPurchaseFlow._();

  static final OcrPurchaseFlow instance = OcrPurchaseFlow._();

  final OcrAccountLinkService _accountLinkService = OcrAccountLinkService();
  final OcrAuthSecretStorage _ocrAuthSecretStorage = OcrAuthSecretStorage();
  final OcrBillingClient _billingClient = OcrBillingClient();
  final OcrStoreService _storeService = OcrStoreService.instance;

  Future<OcrPreparationResult?> prepareOcrReservation(
    BuildContext context, {
    required int pageCount,
    required int bookId,
    required String Function() getServerUrl,
  }) async {
    await _storeService.initialize();
    final linkResult = await _accountLinkService.ensureLinkedAccount();
    if (linkResult.linkedThisCall) {
      await _storeService.restorePurchases();
    }
    Map<String, ProductDetails>? unlockProducts;

    while (context.mounted) {
      final status = await _billingClient.fetchStatus();
      if (!status.ocrUnlocked) {
        unlockProducts ??= await _storeService.queryProducts(
          ocrVisibleProductIds,
        );
        if (!context.mounted) return null;
        final action = await _showUnlockDialog(
          context,
          product: unlockProducts[ocrUnlockProductId]!,
        );
        if (action == null || action == _UnlockDialogAction.cancel) {
          return null;
        }
        if (action == _UnlockDialogAction.restore) {
          await _storeService.restorePurchases();
          continue;
        }
        await _storeService.purchaseProduct(ocrUnlockProductId);
        continue;
      }

      final serverUrl = getServerUrl();
      final usesBuiltInServer = ocr_server_config.isBuiltInOcrServerUrl(
        serverUrl,
      );
      if (!usesBuiltInServer) {
        final customBearerKey =
            await _ocrAuthSecretStorage.loadCustomServerBearerKey();
        if (customBearerKey == null) {
          if (!context.mounted) return null;
          final action = await _showCustomServerKeyRequiredDialog(context);
          if (action == null || action == _CustomServerDialogAction.cancel) {
            return null;
          }
          if (!context.mounted) {
            return null;
          }
          final navigator = Navigator.of(context);
          await navigator.push(
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          );
          continue;
        }
        return const OcrPreparationResult();
      }

      if (status.creditBalance < pageCount) {
        if (!context.mounted) return null;
        final action = await _showInsufficientCreditsDialog(
          context,
          currentBalance: status.creditBalance,
          requiredPages: pageCount,
        );
        if (action == null || action == _LowCreditDialogAction.cancel) {
          return null;
        }
        if (action == _LowCreditDialogAction.refresh) {
          await _billingClient.fetchStatus(forceRefresh: true);
          continue;
        }
        if (action == _LowCreditDialogAction.openSettings) {
          if (!context.mounted) {
            return null;
          }
          final navigator = Navigator.of(context);
          await navigator.push(
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          );
          continue;
        }

        await launchUrl(
          Uri.parse(ocr_server_config.mekuruOcrRepoUrl),
          mode: LaunchMode.externalApplication,
        );
        return null;
      }

      try {
        final reservation = await _billingClient.reserveOcrJob(
          requestedPages: pageCount,
          bookId: bookId,
        );
        return OcrPreparationResult(reservation: reservation);
      } on OcrBillingException catch (e) {
        if (e.isUnlockRequired || e.isInsufficientCredits) {
          continue;
        }
        rethrow;
      }
    }

    return null;
  }

  Future<_UnlockDialogAction?> _showUnlockDialog(
    BuildContext context, {
    required ProductDetails product,
  }) {
    return showDialog<_UnlockDialogAction>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Unlock OCR'),
        content: Text(
          'OCR requires a one-time unlock. ${product.title} costs '
          '${product.price} and includes 250 starter credits.',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_UnlockDialogAction.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_UnlockDialogAction.restore),
            child: const Text('Restore'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_UnlockDialogAction.buyUnlock),
            child: Text('Buy ${product.price}'),
          ),
        ],
      ),
    );
  }

  Future<_LowCreditDialogAction?> _showInsufficientCreditsDialog(
    BuildContext context, {
    required int currentBalance,
    required int requiredPages,
  }) {
    final needed = requiredPages - currentBalance;
    final theme = Theme.of(context);
    return showDialog<_LowCreditDialogAction>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('More OCR Credits Needed'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This OCR pass needs $requiredPages credits. '
              'You currently have $currentBalance, so you need $needed more.',
            ),
            const SizedBox(height: 12),
            Text(
              'OCR unlock includes 250 starter page credits. '
              'You can switch to a custom OCR server to continue without '
              'using page credits.',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_LowCreditDialogAction.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_LowCreditDialogAction.refresh),
            child: const Text('Refresh'),
          ),
          TextButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(_LowCreditDialogAction.openSettings),
            child: const Text('OCR Server Settings'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(_LowCreditDialogAction.selfHost),
            child: const Text('Run Your Own Server'),
          ),
        ],
      ),
    );
  }

  Future<_CustomServerDialogAction?> _showCustomServerKeyRequiredDialog(
    BuildContext context,
  ) {
    return showDialog<_CustomServerDialogAction>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Custom Server Setup Required'),
        content: const Text(
          'Custom OCR servers require a shared key. Open OCR Server Settings '
          'and enter the same AUTH_API_KEY value configured on your server.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(_CustomServerDialogAction.cancel),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(_CustomServerDialogAction.openSettings),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
}

enum _UnlockDialogAction { cancel, restore, buyUnlock }

enum _LowCreditDialogAction { cancel, refresh, openSettings, selfHost }

enum _CustomServerDialogAction { cancel, openSettings }
