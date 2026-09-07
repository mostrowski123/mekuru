import 'package:flutter/material.dart';
import 'package:mekuru/features/backup/data/services/full_backup_service.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/utils/format_bytes.dart';

/// Two-step confirmation before a full restore deletes everything in Mekuru
/// on this device: first a review of what the file holds and what the device
/// holds, then a destructive confirmation whose button stays disabled until
/// the user acknowledges the deletion. Returns true only after that button.
Future<bool> showFullRestoreConfirmFlow(
  BuildContext context,
  FullBackupPreview preview,
) async {
  final reviewed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => FullRestoreReviewDialog(preview: preview),
  );
  if (reviewed != true || !context.mounted) return false;
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => FullRestoreReplaceDialog(preview: preview),
  );
  return confirmed == true;
}

class FullRestoreReviewDialog extends StatelessWidget {
  final FullBackupPreview preview;

  const FullRestoreReviewDialog({super.key, required this.preview});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final manifest = preview.manifest;
    final created = MaterialLocalizations.of(
      context,
    ).formatMediumDate(manifest.createdAt.toLocal());
    final labelStyle = theme.textTheme.labelLarge?.copyWith(
      color: theme.colorScheme.primary,
    );

    return AlertDialog(
      title: Text(l10n.backupFullReviewTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.backupFullReviewInFile, style: labelStyle),
            const SizedBox(height: 4),
            Text(
              '${l10n.backupFullCountBooks(count: manifest.bookCount)}, '
              '${l10n.backupFullCountDictionaries(count: manifest.dictionaryCount)}, '
              '${formatBytes(preview.sizeBytes)}',
            ),
            Text(
              l10n.backupFullReviewCreated(
                date: created,
                version: manifest.appVersion,
              ),
              style: theme.textTheme.bodySmall,
            ),
            if (manifest.externalMangaCount > 0) ...[
              const SizedBox(height: 8),
              Text(
                l10n.backupFullReviewExternalManga(
                  count: manifest.externalMangaCount,
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(l10n.backupFullReviewOnDevice, style: labelStyle),
            const SizedBox(height: 4),
            Text(
              '${l10n.backupFullCountBooks(count: preview.currentBookCount)}, '
              '${l10n.backupFullCountDictionaries(count: preview.currentDictionaryCount)}',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.backupFullReviewContinue),
        ),
      ],
    );
  }
}

class FullRestoreReplaceDialog extends StatefulWidget {
  final FullBackupPreview preview;

  const FullRestoreReplaceDialog({super.key, required this.preview});

  @override
  State<FullRestoreReplaceDialog> createState() =>
      _FullRestoreReplaceDialogState();
}

class _FullRestoreReplaceDialogState extends State<FullRestoreReplaceDialog> {
  bool _acknowledged = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final preview = widget.preview;

    return AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error),
      title: Text(l10n.backupFullReplaceTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.backupFullReplaceBody(
                books: l10n.backupFullCountBooks(
                  count: preview.currentBookCount,
                ),
                dictionaries: l10n.backupFullCountDictionaries(
                  count: preview.currentDictionaryCount,
                ),
              ),
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              value: _acknowledged,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(l10n.backupFullReplaceAcknowledge),
              onChanged: (value) =>
                  setState(() => _acknowledged = value ?? false),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: _acknowledged
              ? () => Navigator.of(context).pop(true)
              : null,
          child: Text(l10n.backupFullReplaceConfirm),
        ),
      ],
    );
  }
}
