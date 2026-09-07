import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/backup/data/models/backup_kind.dart';
import 'package:mekuru/features/backup/data/services/backup_file_manager.dart';
import 'package:mekuru/features/backup/data/services/backup_scheduler.dart';
import 'package:mekuru/features/backup/data/services/backup_serializer.dart';
import 'package:mekuru/features/backup/data/services/restore_service.dart';
import 'package:mekuru/features/backup/presentation/providers/backup_providers.dart';
import 'package:mekuru/features/backup/presentation/widgets/full_backup_progress_dialog.dart';
import 'package:mekuru/features/backup/presentation/widgets/full_restore_confirm_flow.dart';
import 'package:mekuru/features/backup/presentation/widgets/restore_conflict_dialog.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/utils/format_bytes.dart';
import 'package:mekuru/shared/utils/haptics.dart';
import 'package:mekuru/shared/widgets/settings/settings_rows.dart';

/// Backup & Restore. Two visibly different kinds live here:
/// - reading data backup (`.mekuru`, small, merges, can run automatically)
/// - full backup (`.zip`, everything, replaces Mekuru's data, manual only)
/// Every label carries its kind and file type so the two are never mixed up.
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
    // Only the flag: progress ticks must repaint the overlay, not this page.
    final fullWorking = ref.watch(
      fullBackupNotifierProvider.select((s) => s.isWorking),
    );
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
      _announce(
        prev?.error,
        next.error,
        prev?.successMessage,
        next.successMessage,
      );
    });
    ref.listen(restoreNotifierProvider, (prev, next) {
      _announce(
        prev?.error,
        next.error,
        prev?.successMessage,
        next.successMessage,
      );
    });
    ref.listen(fullBackupNotifierProvider, (prev, next) {
      _announce(
        prev?.error,
        next.error,
        prev?.successMessage,
        next.successMessage,
      );
    });

    final isWorking =
        backupState.isWorking || restoreState.isWorking || fullWorking;

    return PopScope(
      // A multi-gigabyte export or restore must not be backed out of by
      // accident; Cancel on the overlay is the way out.
      canPop: !fullWorking,
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.backupTitle)),
        body: Stack(
          children: [
            _buildContent(
              context,
              theme: theme,
              l10n: l10n,
              isWorking: isWorking,
              autoInterval: autoInterval,
              backupHistory: backupHistory,
            ),
            const FullBackupProgressOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context, {
    required ThemeData theme,
    required AppLocalizations l10n,
    required bool isWorking,
    required AsyncValue<BackupInterval> autoInterval,
    required AsyncValue<List<BackupFileInfo>> backupHistory,
  }) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (isWorking) const LinearProgressIndicator(),
        _KindCard(
          icon: Icons.info_outline,
          title: l10n.backupScopeNoteTitle,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(l10n.backupScopeNoteBody),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _KindCard(
          icon: Icons.description_outlined,
          title: l10n.backupSectionBackup,
          badge: l10n.backupReadingDataBadge,
          children: [
            ListTile(
              leading: Icon(
                Icons.backup_outlined,
                color: theme.colorScheme.primary,
              ),
              title: Text(l10n.backupCreateNowTitle),
              subtitle: Text(l10n.backupCreateNowSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: isWorking
                  ? null
                  : () {
                      AppHaptics.light();
                      ref.read(backupNotifierProvider.notifier).createBackup();
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
                _showIntervalPicker(context);
              },
            ),
            const Divider(height: 1),
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
                      _pickAndConfirmReadingDataImport(context);
                    },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                l10n.backupScopeNoteRestore,
                style: theme.textTheme.bodySmall,
              ),
            ),
            const Divider(height: 1),
            SettingsSectionHeader(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              title: l10n.backupSectionHistory,
            ),
            backupHistory.when(
              data: (backups) {
                if (backups.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
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
                                  _confirmReadingDataImport(
                                    context,
                                    filePath: info.filePath,
                                    fileName: info.fileName,
                                  );
                                },
                          onDelete: isWorking
                              ? null
                              : () {
                                  AppHaptics.light();
                                  _confirmDelete(context, info);
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
          ],
        ),
        const SizedBox(height: 16),
        _KindCard(
          icon: Icons.inventory_2_outlined,
          title: l10n.backupFullSectionTitle,
          badge: l10n.backupFullBadge,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(l10n.backupFullScopeBody),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                l10n.backupFullNotIncluded,
                style: theme.textTheme.bodySmall,
              ),
            ),
            ListTile(
              leading: Icon(
                Icons.drive_folder_upload_outlined,
                color: theme.colorScheme.primary,
              ),
              title: Text(l10n.backupFullExportTitle),
              subtitle: Text(l10n.backupFullExportSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: isWorking
                  ? null
                  : () {
                      AppHaptics.light();
                      ref
                          .read(fullBackupNotifierProvider.notifier)
                          .exportToFolder();
                    },
            ),
            ListTile(
              leading: Icon(
                Icons.settings_backup_restore_outlined,
                color: theme.colorScheme.error,
              ),
              title: Text(l10n.backupFullRestoreTitle),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.backupFullRestoreSubtitle),
                  const SizedBox(height: 6),
                  Chip(
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    avatar: Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    label: Text(l10n.backupFullReplacesChip),
                    labelStyle: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    backgroundColor: theme.colorScheme.errorContainer,
                    side: BorderSide.none,
                  ),
                ],
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: isWorking
                  ? null
                  : () {
                      AppHaptics.light();
                      _restoreFullBackup();
                    },
            ),
          ],
        ),
      ],
    );
  }

  // ──────────────── Full backup flows ────────────────

  Future<void> _restoreFullBackup() async {
    final notifier = ref.read(fullBackupNotifierProvider.notifier);
    final preview = await notifier.pickAndInspect();
    if (preview == null || !mounted) return;

    final confirmed = await showFullRestoreConfirmFlow(context, preview);
    if (!confirmed || !mounted) return;

    final staged = await notifier.stageForRestart();
    if (!staged || !mounted) return;

    await _showRestartDialog();
    await notifier.exitApp();
  }

  Future<void> _showRestartDialog() {
    final l10n = context.l10n;
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(l10n.backupFullRestartTitle),
          content: Text(l10n.backupFullRestartBody),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.backupFullRestartButton),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────── Messages ────────────────

  void _announce(
    BackupMessage? prevError,
    BackupMessage? error,
    BackupMessage? prevSuccess,
    BackupMessage? success,
  ) {
    if (error != null && error != prevError) {
      _showSnackbar(_localizeMessage(error), isError: true);
    } else if (success != null && success != prevSuccess) {
      _showSnackbar(_localizeMessage(success));
    }
  }

  String _localizeMessage(BackupMessage message) {
    final l10n = context.l10n;
    final details = message.details ?? '';
    return switch (message.kind) {
      BackupMessageKind.backupCreated => l10n.backupCreatedSuccess,
      BackupMessageKind.backupFailed => l10n.backupFailed(details: details),
      BackupMessageKind.noBackupsToExport => l10n.backupNoBackupsToExport,
      BackupMessageKind.backupExported => l10n.backupExportedSuccess,
      BackupMessageKind.exportFailed => l10n.backupExportFailed(
        details: details,
      ),
      BackupMessageKind.invalidBackupFile => l10n.backupInvalidFile,
      BackupMessageKind.couldNotOpenFile => l10n.backupCouldNotOpenFile(
        details: details,
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
        details: details,
      ),
      BackupMessageKind.booksUpdatedFromBackup =>
        l10n.backupBooksUpdatedFromBackup(count: message.count ?? 0),
      BackupMessageKind.applyBookDataFailed => l10n.backupApplyBookDataFailed(
        details: details,
      ),
      BackupMessageKind.wrongKindFullBackup => l10n.backupWrongKindFullBackup,
      BackupMessageKind.wrongKindReadingData => l10n.backupWrongKindReadingData,
      BackupMessageKind.fullExported => l10n.backupFullExported(size: details),
      BackupMessageKind.fullExportedWithSkipped =>
        l10n.backupFullExportedWithSkipped(count: message.count ?? 0),
      BackupMessageKind.fullCancelled => l10n.backupFullCancelled,
      BackupMessageKind.fullBusy => l10n.backupFullBusy,
      BackupMessageKind.fullNotEnoughSpace => l10n.backupFullNotEnoughSpace(
        size: details,
      ),
      BackupMessageKind.fullTooNew => l10n.backupFullTooNew(version: details),
      BackupMessageKind.fullInvalid => l10n.backupFullInvalid,
      BackupMessageKind.fullPendingRestore => l10n.backupFullPendingRestore,
      BackupMessageKind.fullFailed => l10n.backupFullFailed(details: details),
      BackupMessageKind.fullRestoreFailed => l10n.backupFullRestoreFailed(
        details: details,
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

  // ──────────────── Reading data flows ────────────────

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

  Future<void> _pickAndConfirmReadingDataImport(BuildContext context) async {
    final l10n = context.l10n;

    try {
      final picked = await BackupFileManager.pickReadingDataBackup();
      final filePath = picked?.path;
      if (picked == null || filePath == null || !context.mounted) return;
      _confirmReadingDataImport(
        context,
        filePath: filePath,
        fileName: picked.name,
      );
    } on WrongBackupKindException {
      _showSnackbar(l10n.backupWrongKindFullBackup, isError: true);
    } on BackupFormatException {
      _showSnackbar(l10n.backupInvalidFile, isError: true);
    } catch (e) {
      _showSnackbar(
        l10n.backupCouldNotOpenFile(details: e.toString()),
        isError: true,
      );
    }
  }

  void _confirmReadingDataImport(
    BuildContext context, {
    required String filePath,
    required String fileName,
  }) {
    final l10n = context.l10n;
    // Resolved before the dialog opens: the screen can unmount while it's up.
    final container = ProviderScope.containerOf(context, listen: false);
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
                container
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

  void _confirmDelete(BuildContext context, BackupFileInfo info) {
    final l10n = context.l10n;
    // Resolved before the dialog opens: the screen can unmount while it's up.
    final container = ProviderScope.containerOf(context, listen: false);

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
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await container
                  .read(backupFileManagerProvider)
                  .deleteBackupFile(info.filePath);
              container.invalidate(backupHistoryProvider);
            },
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
  }

  void _showIntervalPicker(BuildContext context) {
    final l10n = context.l10n;
    // Resolved before the dialog opens: the screen can unmount while it's up.
    final container = ProviderScope.containerOf(context, listen: false);

    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l10n.backupAutoBackupIntervalTitle),
        children: BackupInterval.values.map((interval) {
          return SimpleDialogOption(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await container
                  .read(backupSchedulerProvider)
                  .setInterval(interval);
              container.invalidate(autoBackupIntervalProvider);
            },
            child: Text(_backupIntervalLabel(l10n, interval)),
          );
        }).toList(),
      ),
    );
  }
}

/// A titled card: an icon, a name and optionally a file-type badge, then
/// its content. Each backup kind gets its own card, which is what stops a
/// user exporting or restoring the wrong one.
class _KindCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? badge;
  final List<Widget> children;

  const _KindCard({
    required this.icon,
    required this.title,
    this.badge,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (badge case final badge?)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      badge,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
              ],
            ),
          ),
          ...children,
        ],
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
      subtitle: Text('$dateStr - ${formatBytes(info.sizeBytes)}'),
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
