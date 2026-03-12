import 'package:flutter/material.dart';
import 'package:mekuru/features/manga/data/services/ocr_auth_secret_storage.dart';
import 'package:mekuru/features/manga/presentation/screens/pro_upgrade_screen.dart';
import 'package:mekuru/features/settings/data/services/ocr_server_config.dart'
    as ocr_server_config;
import 'package:mekuru/features/settings/presentation/screens/settings_screen.dart';
import 'package:mekuru/l10n/l10n.dart';

import '../../data/services/ocr_billing_client.dart';

class OcrPurchaseFlow {
  OcrPurchaseFlow({
    OcrAuthSecretStorage? ocrAuthSecretStorage,
    OcrBillingClient? billingClient,
    Future<bool> Function()? readProUnlocked,
    Future<String?> Function()? loadCustomServerBearerKey,
    Future<void> Function(BuildContext context)? openProUpgradeScreen,
    Future<void> Function(BuildContext context)? openSettingsScreen,
  }) : _ocrAuthSecretStorage = ocrAuthSecretStorage ?? OcrAuthSecretStorage(),
       _billingClient = billingClient ?? OcrBillingClient(),
       _readProUnlockedOverride = readProUnlocked,
       _loadCustomServerBearerKeyOverride = loadCustomServerBearerKey,
       _openProUpgradeScreenOverride = openProUpgradeScreen,
       _openSettingsScreenOverride = openSettingsScreen;

  static final OcrPurchaseFlow instance = OcrPurchaseFlow();

  final OcrAuthSecretStorage _ocrAuthSecretStorage;
  final OcrBillingClient _billingClient;
  final Future<bool> Function()? _readProUnlockedOverride;
  final Future<String?> Function()? _loadCustomServerBearerKeyOverride;
  final Future<void> Function(BuildContext context)?
  _openProUpgradeScreenOverride;
  final Future<void> Function(BuildContext context)?
  _openSettingsScreenOverride;

  Future<bool> ensureProAndCustomOcrReady(
    BuildContext context, {
    required String Function() getServerUrl,
  }) async {
    while (context.mounted) {
      if (!await _readProUnlocked()) {
        if (!context.mounted) return false;
        await _openProUpgradeScreen(context);
        if (!context.mounted) return false;
        if (!await _readProUnlocked()) {
          return false;
        }
        continue;
      }
      if (!context.mounted) return false;

      final serverUrl = getServerUrl().trim();
      if (ocr_server_config.isUnsetOrBuiltInOcrServerUrl(serverUrl)) {
        final action = await _showCustomServerRequiredDialog(context);
        if (action != _ServerSetupDialogAction.openSettings) {
          return false;
        }
        if (!context.mounted) return false;
        await _openSettingsScreen(context);
        continue;
      }

      final customBearerKey = await _loadCustomServerBearerKey();
      if (customBearerKey == null || customBearerKey.trim().isEmpty) {
        if (!context.mounted) return false;
        final action = await _showCustomServerKeyRequiredDialog(context);
        if (action != _CustomServerDialogAction.openSettings) {
          return false;
        }
        if (!context.mounted) return false;
        await _openSettingsScreen(context);
        continue;
      }

      return true;
    }

    return false;
  }

  Future<bool> _readProUnlocked() async {
    if (_readProUnlockedOverride != null) {
      return _readProUnlockedOverride();
    }

    final localStatus = await _billingClient.readLastKnownStatus();
    if (localStatus?.ocrUnlocked ?? false) {
      return true;
    }

    final refreshedStatus = await _billingClient.refreshStatusIfAuthenticated(
      forceRefresh: localStatus == null,
    );
    return refreshedStatus?.ocrUnlocked ?? false;
  }

  Future<String?> _loadCustomServerBearerKey() {
    if (_loadCustomServerBearerKeyOverride != null) {
      return _loadCustomServerBearerKeyOverride();
    }

    return _ocrAuthSecretStorage.loadCustomServerBearerKey();
  }

  Future<void> _openProUpgradeScreen(BuildContext context) {
    if (_openProUpgradeScreenOverride != null) {
      return _openProUpgradeScreenOverride(context);
    }

    return Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ProUpgradeScreen()));
  }

  Future<void> _openSettingsScreen(BuildContext context) {
    if (_openSettingsScreenOverride != null) {
      return _openSettingsScreenOverride(context);
    }

    return Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  Future<_ServerSetupDialogAction?> _showCustomServerRequiredDialog(
    BuildContext context,
  ) {
    return showDialog<_ServerSetupDialogAction>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.ocrCustomServerRequiredTitle),
        content: Text(dialogContext.l10n.ocrCustomServerRequiredBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(_ServerSetupDialogAction.cancel),
            child: Text(dialogContext.l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(_ServerSetupDialogAction.openSettings),
            child: Text(dialogContext.l10n.commonOpenSettings),
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
        title: Text(dialogContext.l10n.ocrCustomServerKeyRequiredTitle),
        content: Text(dialogContext.l10n.ocrCustomServerKeyRequiredBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(_CustomServerDialogAction.cancel),
            child: Text(dialogContext.l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(_CustomServerDialogAction.openSettings),
            child: Text(dialogContext.l10n.commonOpenSettings),
          ),
        ],
      ),
    );
  }
}

enum _ServerSetupDialogAction { cancel, openSettings }

enum _CustomServerDialogAction { cancel, openSettings }
