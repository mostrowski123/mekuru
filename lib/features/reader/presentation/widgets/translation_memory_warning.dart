import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/platform/device_memory.dart';
import 'package:mekuru/core/platform/full_backup_job_api.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/features/reader/data/services/gemma_translation.dart';
import 'package:mekuru/features/reader/presentation/providers/gemma_download_provider.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/widgets/mobile_data_dialog.dart';

/// Before sentence translation is set up on a phone low on memory, says it
/// may be slow or close Mekuru and where to turn it off. True to go ahead;
/// "Turn off" switches the Sentence tab off and returns false, as does
/// dismissing the dialog.
Future<bool> confirmTranslationMemory(BuildContext context) async {
  if (!await deviceLowOnMemory()) return true;
  if (!context.mounted) return false;
  final l = context.l10n;
  final proceed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l.sentenceTranslationLowMemoryTitle),
      content: Text(l.sentenceTranslationLowMemoryBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(l.sentenceTranslationTurnOff),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(l.commonContinue),
        ),
      ],
    ),
  );
  if (proceed == false && context.mounted) {
    ProviderScope.containerOf(context, listen: false)
        .read(sentenceTranslationModeProvider.notifier)
        .setMode(SentenceTranslationMode.off);
  }
  return proceed == true;
}

/// Before High quality is set up on a phone with under 8 GB or 3 GB free.
/// True to go ahead; "Use Standard" or dismissing switches the model to
/// Standard (it may already be High), cancels a running download, and
/// returns false. Android only: it builds the Gemma download provider.
Future<bool> confirmHighQualityMemory(BuildContext context) async {
  if (!await deviceLowOnMemory(minTotalMb: 7168, minFreeMb: 3072)) return true;
  if (!context.mounted) return false;
  final l = context.l10n;
  final proceed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l.sentenceTranslationLowMemoryTitle),
      content: Text(l.translationHighQualityLowMemoryBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(l.translationHighQualityUseStandard),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(l.commonContinue),
        ),
      ],
    ),
  );
  if (proceed != true && context.mounted) {
    final container = ProviderScope.containerOf(context, listen: false);
    container
        .read(translationModelProvider.notifier)
        .setChoice(TranslationModelChoice.standard);
    unawaited(GemmaTranslation.instance.close());
    container.read(gemmaDownloadProvider.notifier).cancel();
  }
  return proceed == true;
}

/// Starts the High quality download on Wi-Fi, or over mobile data once the
/// user agrees to it: only that answer lets the job use mobile data. Also
/// asks, without waiting, to post the notification a failed download sends.
/// Pass the notifier read before any dialog: the caller can unmount.
Future<void> askThenStartHighQuality(
  BuildContext context,
  GemmaDownloadNotifier download,
) async {
  final onWifi = await isOnWifi();
  if (!onWifi) {
    if (!context.mounted) return;
    final size = GemmaTranslation.downloadSize();
    final ok = await confirmMobileData(
      context,
      size: size,
      body: context.l10n.translationMobileDataBody(size: size),
    );
    if (!ok) return;
  }
  unawaited(const FullBackupJobChannel().requestNotificationPermission());
  // The provider chooses High once the download is done.
  unawaited(download.start(mobileData: !onWifi));
}
