import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/backup/data/services/backup_file_manager.dart';
import 'package:mekuru/features/backup/data/services/backup_scheduler.dart';
import 'package:mekuru/features/backup/presentation/providers/backup_providers.dart';
import 'package:mekuru/features/backup/presentation/widgets/restore_conflict_dialog.dart';
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
    final backupState = ref.watch(backupNotifierProvider);
    final restoreState = ref.watch(restoreNotifierProvider);
    final backupHistory = ref.watch(backupHistoryProvider);
    final autoInterval = ref.watch(autoBackupIntervalProvider);

    // Show conflict dialog when pending conflicts arrive
    ref.listen(restoreNotifierProvider, (prev, next) {
      if (next.pendingConflicts != null &&
          next.pendingConflicts!.isNotEmpty &&
          (prev?.pendingConflicts == null || prev!.pendingConflicts!.isEmpty)) {
        _showConflictDialog(next.pendingConflicts!);
      }
    });

    // Show snackbar for backup errors/success
    ref.listen(backupNotifierProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error) {
        _showSnackbar(next.error!, isError: true);
      } else if (next.successMessage != null &&
          next.successMessage != prev?.successMessage) {
        _showSnackbar(next.successMessage!);
      }
    });

    // Show snackbar for restore errors/success
    ref.listen(restoreNotifierProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error) {
        _showSnackbar(next.error!, isError: true);
      } else if (next.successMessage != null &&
          next.successMessage != prev?.successMessage) {
        _showSnackbar(next.successMessage!);
      }
    });

    final isWorking = backupState.isWorking || restoreState.isWorking;

    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: ListView(
        children: [
          if (isWorking) const LinearProgressIndicator(),

          // ── Backup ──
          _SectionHeader(title: 'Backup'),
          ListTile(
            leading: Icon(
              Icons.backup_outlined,
              color: theme.colorScheme.primary,
            ),
            title: const Text('Create Backup Now'),
            subtitle: const Text('Save all settings and reading data'),
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
            title: const Text('Export Backup'),
            subtitle: const Text('Save your latest backup to a file'),
            trailing: const Icon(Icons.chevron_right),
            onTap: isWorking
                ? null
                : () {
                    AppHaptics.light();
                    ref
                        .read(backupNotifierProvider.notifier)
                        .exportLatestBackup();
                  },
          ),
          const Divider(),

          // ── Auto-Backup ──
          _SectionHeader(title: 'Auto-Backup'),
          ListTile(
            leading: Icon(
              Icons.schedule_outlined,
              color: theme.colorScheme.primary,
            ),
            title: const Text('Auto-Backup Interval'),
            subtitle: autoInterval.when(
              data: (interval) => Text(BackupScheduler.intervalLabel(interval)),
              loading: () => const Text('Loading...'),
              error: (_, _) => const Text('Error'),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              AppHaptics.light();
              _showIntervalPicker(context, ref);
            },
          ),
          const Divider(),

          // ── Restore ──
          _SectionHeader(title: 'Restore'),
          ListTile(
            leading: Icon(
              Icons.file_open_outlined,
              color: theme.colorScheme.primary,
            ),
            title: const Text('Import Backup File'),
            subtitle: const Text('Restore from a .mekuru file'),
            trailing: const Icon(Icons.chevron_right),
            onTap: isWorking
                ? null
                : () {
                    AppHaptics.light();
                    ref
                        .read(restoreNotifierProvider.notifier)
                        .restoreFromFilePicker();
                  },
          ),
          const Divider(),

          // ── Backup History ──
          _SectionHeader(title: 'Backup History'),
          backupHistory.when(
            data: (backups) {
              if (backups.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text('No backups yet'),
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
                                _confirmRestore(context, info);
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
              child: Text('Error loading backups: $e'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
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

  void _confirmRestore(BuildContext context, BackupFileInfo info) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore Backup?'),
        content: Text(
          'This will restore settings and reading data from '
          '${info.fileName}. Your current settings will be overwritten.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref
                  .read(restoreNotifierProvider.notifier)
                  .restoreFromPath(info.filePath);
            },
            child: const Text('Restore'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    BackupFileInfo info,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Backup?'),
        content: Text('Delete ${info.fileName}? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showIntervalPicker(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Auto-Backup Interval'),
        children: BackupInterval.values.map((interval) {
          return SimpleDialogOption(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await ref.read(backupSchedulerProvider).setInterval(interval);
              ref.invalidate(autoBackupIntervalProvider);
            },
            child: Text(BackupScheduler.intervalLabel(interval)),
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
    final sizeKb = (info.sizeBytes / 1024).toStringAsFixed(1);
    final dateStr = _formatDate(info.createdAt);

    return ListTile(
      leading: Icon(
        info.isAuto ? Icons.auto_mode_outlined : Icons.save_outlined,
        color: theme.colorScheme.primary,
      ),
      title: Text(
        info.isAuto ? 'Auto backup' : 'Manual backup',
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
          const PopupMenuItem(value: 'restore', child: Text('Restore')),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
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
