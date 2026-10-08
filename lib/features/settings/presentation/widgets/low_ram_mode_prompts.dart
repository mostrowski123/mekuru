import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/platform/device_memory.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/backup/presentation/providers/full_backup_job_provider.dart';
import 'package:mekuru/features/reader/data/services/gemma_translation.dart';
import 'package:mekuru/features/reader/data/services/mecab_service.dart';
import 'package:mekuru/features/reader/data/services/mozilla_translation.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/l10n/l10n.dart';

/// Turns Low RAM mode on or off; [source] is `settings` or `hint`. Turning
/// it on frees translation's memory at once. UniDic-lite can't be unloaded,
/// so while it is in use Mekuru offers to close.
Future<void> setLowRamMode(
  BuildContext context,
  WidgetRef ref, {
  required bool on,
  required String source,
}) async {
  // Read before any await: the caller can unmount.
  final exitApp = ref.read(appExitProvider);
  await ref.read(lowRamModeProvider.notifier).setLowRamMode(on);
  logUsage('low_ram_mode.toggled', attrs: {'enabled': on, 'source': source});
  if (!on) return;
  unawaited(MozillaTranslation.instance.stop());
  unawaited(GemmaTranslation.instance.close());

  final mecab = MecabService.instance;
  if (!mecab.isInitialized ||
      mecab.expectedLayout != MecabFeatureLayout.unidicLite ||
      !context.mounted) {
    return;
  }
  final l10n = context.l10n;
  final close = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      content: Text(l10n.lowRamModeCloseBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(l10n.lowRamModeNotNow),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(l10n.lowRamModeCloseNow),
        ),
      ],
    ),
  );
  if (close == true) await exitApp();
}

/// Offers Low RAM mode once, on an Android device with 4 GB of RAM or less
/// (Android reports a 4 GB phone as about 3.6-3.8 GB), while the mode is off
/// and nothing covers [context]'s route.
Future<void> offerLowRamMode(BuildContext context, WidgetRef ref) async {
  if (defaultTargetPlatform != TargetPlatform.android ||
      ref.read(lowRamModeProvider)) {
    return;
  }
  final storage = ref.read(appSettingsStorageProvider);
  if (!await deviceLowOnMemory(minTotalMb: 4608, minFreeMb: 0) ||
      await storage.loadLowRamHintShown() == true ||
      !context.mounted ||
      !(ModalRoute.of(context)?.isCurrent ?? true)) {
    return;
  }
  await storage.saveLowRamHintShown(true);
  if (!context.mounted) return;
  final l10n = context.l10n;
  final turnOn = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.lowRamModeHintTitle),
      content: Text(l10n.lowRamModeHintBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(l10n.lowRamModeNotNow),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(l10n.lowRamModeTurnOn),
        ),
      ],
    ),
  );
  if (turnOn == true && context.mounted) {
    await setLowRamMode(context, ref, on: true, source: 'hint');
  }
}
