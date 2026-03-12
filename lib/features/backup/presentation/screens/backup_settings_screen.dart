import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/backup/data/services/backup_file_manager.dart';
import 'package:mekuru/features/backup/data/services/backup_scheduler.dart';
import 'package:mekuru/features/backup/data/services/restore_service.dart';
import 'package:mekuru/features/backup/presentation/providers/backup_providers.dart';
import 'package:mekuru/features/backup/presentation/widgets/restore_conflict_dialog.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/utils/haptics.dart';

class BackupSettingsScreen extends ConsumerStatefulWidget {
  const BackupSettingsScreen({super.key});

  @override
  ConsumerState<BackupSettingsScreen> createState() =>
      _BackupSettingsScreenState();
}

class _BackupSettingsScreenState extends ConsumerState<BackupSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final backupState = ref.watch(backupNotifierProvider);
    final restoreState = ref.watch(restoreNotifierProvider);
    final backupHistory = ref.watch(backupHistoryProvider);
    final autoInterval = ref.watch(autoBackupIntervalProvider);

    ref.listen(restoreNotifierProvider, (prev, next) {
      if (next.pendingConflicts != null &&
          next.pendingConflicts!.isNotEmpty &&
          (prev?.pendingConflicts == null || prev!.pendingConflicts!.isEmpty)) {
        _showConflictDialog(next.pendingConflicts!);
      }
    });

    ref.listen(backupNotifierProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error) {
        _showSnackbar(_localizeMessage(next.error!), isError: true);
      } else if (next.successMessage != null &&
          next.successMessage != prev?.successMessage) {
        _showSnackbar(_localizeMessage(next.successMessage!));
      }
    });

    ref.listen(restoreNotifierProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error) {
        _showSnackbar(_localizeMessage(next.error!), isError: true);
      } else if (next.successMessage != null &&
          next.successMessage != prev?.successMessage) {
        _showSnackbar(_localizeMessage(next.successMessage!));
      }
    });

    final isWorking = backupState.isWorking || restoreState.isWorking;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.backupTitle)),
      body: ListView(
        children: [
          if (isWorking) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Card(
              color: theme.colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.backupScopeNoteTitle,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.backupScopeNoteBody,
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.backupScopeNoteRestore,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _SectionHeader(title: l10n.backupSectionBackup),
          ListTile(
            leading: Icon(
              Icons.backup_outlined,
              color: theme.colorScheme.primary,
            ),
            title: Text(l10n.backupCreateNowTitle),
            subtitle: Text(l10n.backupCreateNowSubtitle),
            trailing: isWorking
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right),
            onTap: isWorking
                ? null
                : () {
                    AppHaptics.light();
                    ref
                        .read(backupNotifierProvider.notifier)
                        .createBackup()
                        .then((_) => ref.invalidate(backupHistoryProvider));
                  },
          ),
          ListTile(
            leading: Icon(
              Icons.save_alt_outlined,
              color: theme.colorScheme.primary,
            ),
            title: Text(l10n.backupExportTitle),
            subtitle: Text(l10n.backupExportSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: isWorking
                ? null
                : () {
                    AppHaptics.light();
                    ref
                        .read(backupNotifierProvider.notifier)
                        .exportLatestBackup(
                          dialogTitle: l10n.backupSaveFileDialogTitle,
                        );
                  },
          ),
          const Divider(),
          _SectionHeader(title: l10n.backupSectionAutoBackup),
          ListTile(
            leading: Icon(
              Icons.schedule_outlined,
              color: theme.colorScheme.primary,
            ),
            title: Text(l10n.backupAutoBackupIntervalTitle),
            subtitle: autoInterval.when(
              data: (interval) => Text(_backupIntervalLabel(l10n, interval)),
              loading: () => Text(l10n.commonLoading),
              error: (_, _) => Text(l10n.commonError),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              AppHaptics.light();
              _showIntervalPicker(context, ref);
            },
          ),
          const Divider(),
          _SectionHeader(title: l10n.backupSectionRestore),
          ListTile(
            leading: Icon(
              Icons.file_open_outlined,
              color: theme.colorScheme.primary,
            ),
            title: Text(l10n.backupImportFileTitle),
            subtitle: Text(l10n.backupImportFileSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: isWorking
                ? null
                : () {
                    AppHaptics.light();
                    _pickAndConfirmRestore(context);
                  },
          ),
          const Divider(),
          _SectionHeader(title: l10n.backupSectionHistory),
          backupHistory.when(
            data: (backups) {
              if (backups.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Text(l10n.backupNoBackupsYet),
                );
              }
              return Column(
                children: backups
                    .map(
                      (info) => _BackupHistoryTile(
                        info: info,
                        onRestore: isWorking
                            ? null
                            : () {
                                AppHaptics.light();
                                _confirmRestore(
                                  context,
                                  filePath: info.filePath,
                                  fileName: info.fileName,
                                );
                              },
                        onDelete: isWorking
                            ? null
                            : () {
                                AppHaptics.light();
                                _confirmDelete(context, ref, info);
                              },
                      ),
                    )
                    .toList(),
              );
            },
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.backupErrorLoadingHistory(details: e.toString()),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  String _localizeMessage(BackupMessage message) {
    final l10n = context.l10n;
    return switch (message.kind) {
      BackupMessageKind.backupCreated => l10n.backupCreatedSuccess,
      BackupMessageKind.backupFailed => l10n.backupFailed(
        details: message.details ?? '',
      ),
      BackupMessageKind.noBackupsToExport => l10n.backupNoBackupsToExport,
      BackupMessageKind.backupExported => l10n.backupExportedSuccess,
      BackupMessageKind.exportFailed => l10n.backupExportFailed(
        details: message.details ?? '',
      ),
      BackupMessageKind.invalidBackupFile => l10n.backupInvalidFile,
      BackupMessageKind.couldNotOpenFile => l10n.backupCouldNotOpenFile(
        details: message.details ?? '',
      ),
      BackupMessageKind.restoreSummary => _buildRestoreSummary(
        message.result ??
            const RestoreResult(
              settingsRestored: false,
              wordsResult: RestoreWordResult(added: 0, skipped: 0),
              booksResult: RestoreBookResult(
                applied: 0,
                pending: 0,
                conflicts: [],
              ),
            ),
      ),
      BackupMessageKind.restoreFailed => l10n.backupRestoreFailed(
        details: message.details ?? '',
      ),
      BackupMessageKind.booksUpdatedFromBackup =>
        l10n.backupBooksUpdatedFromBackup(count: message.count ?? 0),
      BackupMessageKind.applyBookDataFailed => l10n.backupApplyBookDataFailed(
        details: message.details ?? '',
      ),
    };
  }

  String _buildRestoreSummary(RestoreResult result) {
    final l10n = context.l10n;
    final parts = <String>[];
    if (result.settingsRestored) {
      parts.add(l10n.backupRestoreSummarySettingsRestored);
    } else if (result.errors.isNotEmpty) {
      parts.add(l10n.backupRestoreSummarySettingsPartial);
    }

    final words = result.wordsResult;
    if (words.added > 0 || words.skipped > 0) {
      parts.add(
        l10n.backupRestoreSummaryWords(
          added: words.added,
          skipped: words.skipped,
        ),
      );
    }

    final books = result.booksResult;
    if (books.applied > 0) {
      parts.add(l10n.backupRestoreSummaryBooksRestored(count: books.applied));
    }
    if (books.pending > 0) {
      parts.add(l10n.backupRestoreSummaryBooksPending(count: books.pending));
    }

    final dictionaryPreferences = result.dictionaryPreferencesResult;
    if (dictionaryPreferences.queued) {
      parts.add(
        l10n.backupRestoreSummaryDictionaryPreferencesQueued(
          matching: dictionaryPreferences.matchingCount,
          missing: dictionaryPreferences.missingCount,
        ),
      );
    } else if (dictionaryPreferences.skipped) {
      parts.add(l10n.backupRestoreSummaryDictionaryPreferencesSkipped);
    }

    return parts.isEmpty ? l10n.backupRestoreComplete : parts.join('. ');
  }

  String _backupIntervalLabel(AppLocalizations l10n, BackupInterval interval) {
    return switch (interval) {
      BackupInterval.off => l10n.backupIntervalOff,
      BackupInterval.daily => l10n.backupIntervalDaily,
      BackupInterval.weekly => l10n.backupIntervalWeekly,
    };
  }

  void _showSnackbar(String message, {bool isError = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red[700] : null,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Future<void> _showConflictDialog(List<dynamic> conflicts) async {
    final result = await RestoreConflictDialog.show(
      context,
      ref.read(restoreNotifierProvider).pendingConflicts!,
    );
    if (result != null && result.isNotEmpty) {
      await ref.read(restoreNotifierProvider.notifier).applyConflicts(result);
    } else {
      ref.read(restoreNotifierProvider.notifier).clearState();
    }
  }

  Future<void> _pickAndConfirmRestore(BuildContext context) async {
    final l10n = context.l10n;

    try {
      PlatformFile? picked;
      try {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['mekuru'],
        );
        if (result == null || result.files.isEmpty) return;
        picked = result.files.single;
      } catch (_) {
        final result = await FilePicker.platform.pickFiles(type: FileType.any);
        if (result == null || result.files.isEmpty) return;
        picked = result.files.single;
      }

      if (!context.mounted) return;

      final filePath = picked.path;
      if (filePath == null) return;
      if (!filePath.endsWith('.mekuru')) {
        _showSnackbar(l10n.backupInvalidFile, isError: true);
        return;
      }

      _confirmRestore(context, filePath: filePath, fileName: picked.name);
    } catch (e) {
      _showSnackbar(
        l10n.backupCouldNotOpenFile(details: e.toString()),
        isError: true,
      );
    }
  }

  void _confirmRestore(
    BuildContext context, {
    required String filePath,
    required String fileName,
  }) {
    final l10n = context.l10n;
    var queueDictionaryPreferences = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(l10n.backupRestoreDialogTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.backupRestoreDialogBody(fileName: fileName)),
              const SizedBox(height: 16),
              CheckboxListTile(
                value: queueDictionaryPreferences,
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.backupQueueDictionaryPreferencesTitle),
                subtitle: Text(l10n.backupQueueDictionaryPreferencesBody),
                onChanged: (value) {
                  setDialogState(() {
                    queueDictionaryPreferences = value ?? true;
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                ref
                    .read(restoreNotifierProvider.notifier)
                    .restoreFromPath(
                      filePath,
                      queueDictionaryPreferences: queueDictionaryPreferences,
                    );
              },
              child: Text(l10n.commonRestore),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    BackupFileInfo info,
  ) {
    final l10n = context.l10n;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.backupDeleteDialogTitle),
        content: Text(l10n.backupDeleteDialogBody(fileName: info.fileName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await ref
                  .read(backupFileManagerProvider)
                  .deleteBackupFile(info.filePath);
              ref.invalidate(backupHistoryProvider);
            },
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
  }

  void _showIntervalPicker(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;

    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l10n.backupAutoBackupIntervalTitle),
        children: BackupInterval.values.map((interval) {
          return SimpleDialogOption(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await ref.read(backupSchedulerProvider).setInterval(interval);
              ref.invalidate(autoBackupIntervalProvider);
            },
            child: Text(_backupIntervalLabel(l10n, interval)),
          );
        }).toList(),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _BackupHistoryTile extends StatelessWidget {
  final BackupFileInfo info;
  final VoidCallback? onRestore;
  final VoidCallback? onDelete;

  const _BackupHistoryTile({required this.info, this.onRestore, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final sizeKb = (info.sizeBytes / 1024).toStringAsFixed(1);
    final dateStr = _formatDate(info.createdAt);

    return ListTile(
      leading: Icon(
        info.isAuto ? Icons.auto_mode_outlined : Icons.save_outlined,
        color: theme.colorScheme.primary,
      ),
      title: Text(
        info.isAuto ? l10n.backupHistoryTypeAuto : l10n.backupHistoryTypeManual,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text('$dateStr - ${sizeKb}KB'),
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'restore') onRestore?.call();
          if (value == 'delete') onDelete?.call();
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'restore', child: Text(l10n.commonRestore)),
          PopupMenuItem(value: 'delete', child: Text(l10n.commonDelete)),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$month-$day $hour:$minute';
  }
}
