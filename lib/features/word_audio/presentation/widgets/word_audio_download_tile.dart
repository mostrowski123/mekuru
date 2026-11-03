import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/platform/full_backup_job_api.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/features/manga/presentation/widgets/manga_ocr_ios_download_tile.dart';
import 'package:mekuru/features/word_audio/data/services/word_audio.dart';
import 'package:mekuru/features/word_audio/presentation/providers/word_audio_providers.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/widgets/download_status.dart';
import 'package:mekuru/shared/widgets/mobile_data_dialog.dart';

/// Downloads screen row for the word list behind the lookup's speaker button.
class WordAudioDownloadTile extends ConsumerWidget {
  const WordAudioDownloadTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audio = ref.watch(wordAudioProvider);
    final l10n = context.l10n;
    return ModelDownloadTile(
      icon: Icons.volume_up_outlined,
      title: l10n.wordAudioTitle,
      description: l10n.wordAudioDescription,
      files: const [wordAudioIndexFile],
      installed: () => audio.installed,
      download: audio.download,
      remove: audio.remove,
      readyText: l10n.wordAudioReady,
      mobileDataBody: (size) => l10n.wordAudioMobileBody(size: size),
    );
  }
}

/// Downloads screen row for the optional offline pack.
class WordAudioPackTile extends ConsumerWidget {
  const WordAudioPackTile({super.key});

  Future<void> _download(BuildContext context, WidgetRef ref) async {
    // Read before the dialogs: the row can unmount while one is up.
    final notifier = ref.read(wordAudioPackProvider.notifier);
    final size = ref.read(wordAudioProvider).pack.downloadSize;
    final l10n = context.l10n;
    final agreed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.wordAudioPackTitle),
        content: Text(l10n.wordAudioPackWarning(size: size)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.commonDownload),
          ),
        ],
      ),
    );
    if (agreed != true) return;
    final onWifi = await isOnWifi();
    if (!onWifi) {
      if (!context.mounted) return;
      final ok = await confirmMobileData(
        context,
        size: size,
        body: l10n.wordAudioPackMobileBody(size: size),
      );
      if (!ok) return;
    }
    // Android's job can fail with Mekuru closed, and says so in a notification.
    if (defaultTargetPlatform == TargetPlatform.android) {
      unawaited(const FullBackupJobChannel().requestNotificationPermission());
    }
    unawaited(notifier.start(mobileData: !onWifi));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final state = ref.watch(wordAudioPackProvider);
    final notifier = ref.read(wordAudioPackProvider.notifier);
    final size = ref.watch(wordAudioProvider).pack.downloadSize;
    final fraction = state.fraction;
    final error = dictionaryDownloadError(l, state.error);
    final removeButton = IconButton(
      tooltip: l.commonRemove,
      icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
      onPressed: notifier.remove,
    );
    final downloadButton = FilledButton.tonal(
      onPressed: () => _download(context, ref),
      child: Text(l.commonDownload),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: Icon(
            Icons.download_for_offline_outlined,
            color: theme.colorScheme.primary,
          ),
          title: Text(l.wordAudioPackTitle),
          subtitle: Text(
            fraction != null
                ? l.downloadsDownloadingPercent(
                    percent: (fraction * 100).floor(),
                  )
                : state.installed
                ? l.wordAudioPackReady
                : '${l.wordAudioPackDescription} ($size)',
          ),
          trailing: switch (fraction) {
            final f? when f < 1 => IconButton(
              tooltip: l.commonCancel,
              icon: const Icon(Icons.close),
              onPressed: notifier.cancel,
            ),
            // At 100% the file is being verified: nothing left to cancel.
            _? => const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            null when state.installed => removeButton,
            // A partial download can take up to the whole size.
            null when state.hasFiles => Row(
              mainAxisSize: MainAxisSize.min,
              children: [removeButton, downloadButton],
            ),
            null => downloadButton,
          },
        ),
        if (fraction != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LinearProgressIndicator(
              value: fraction,
              semanticsLabel: l.wordAudioPackTitle,
            ),
          ),
        if (error != null) DownloadErrorText(text: error),
      ],
    );
  }
}
