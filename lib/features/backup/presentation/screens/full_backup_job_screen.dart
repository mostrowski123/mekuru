import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/platform/full_backup_job_api.dart';
import 'package:mekuru/features/backup/presentation/providers/full_backup_job_provider.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/utils/format_bytes.dart';

/// Wraps the whole app: while a full backup or restore is in flight (or its
/// outcome has not been acknowledged) [FullBackupJobScreen] covers it. Lives
/// in `MaterialApp.builder`, above the Navigator, so pushed routes and
/// dialogs are covered too.
///
/// An app that was already on screen stays mounted offstage, so the route the
/// job started from is still there afterwards. An app that has not been shown
/// yet (a job found at cold start) is not built until the page goes away:
/// there is nothing to keep, and building the library behind a page nobody
/// can see is wasted work.
class FullBackupJobGate extends ConsumerStatefulWidget {
  const FullBackupJobGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<FullBackupJobGate> createState() => _FullBackupJobGateState();
}

class _FullBackupJobGateState extends ConsumerState<FullBackupJobGate> {
  var _appShown = false;

  @override
  Widget build(BuildContext context) {
    final blocking = ref.watch(
      fullBackupJobProvider.select((s) => s.blocksApp),
    );
    if (!blocking) _appShown = true;
    return Stack(
      children: [
        if (_appShown) Offstage(offstage: blocking, child: widget.child),
        if (blocking) const FullBackupJobScreen(),
      ],
    );
  }
}

/// The only thing on screen during a job: what is happening, how far it
/// is, a way out, and the outcome. No dialogs: this widget sits above the
/// Navigator, so the cancel confirmation is inline.
class FullBackupJobScreen extends ConsumerStatefulWidget {
  const FullBackupJobScreen({super.key});

  @override
  ConsumerState<FullBackupJobScreen> createState() =>
      _FullBackupJobScreenState();
}

class _FullBackupJobScreenState extends ConsumerState<FullBackupJobScreen> {
  bool _confirmingCancel = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(fullBackupJobProvider);
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final isExport = state.kind == FullBackupJobKind.export;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        isExport
                            ? Icons.drive_folder_upload_outlined
                            : Icons.settings_backup_restore_outlined,
                        color: theme.colorScheme.primary,
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          isExport
                              ? l10n.backupFullJobExportTitle
                              : l10n.backupFullJobRestoreTitle,
                          style: theme.textTheme.headlineSmall,
                        ),
                      ),
                      Chip(
                        label: Text(l10n.backupFullBadge),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  ...switch (state.stage) {
                    FullBackupJobStage.none => const <Widget>[],
                    FullBackupJobStage.preparing => _progress(
                      l10n,
                      theme,
                      phase: l10n.backupFullProgressPreparing,
                      status: null,
                      isExport: isExport,
                      cancellable: false,
                    ),
                    FullBackupJobStage.active => _progress(
                      l10n,
                      theme,
                      phase: _phaseText(l10n, state.status),
                      status: state.status,
                      isExport: isExport,
                      cancellable: true,
                    ),
                    FullBackupJobStage.terminal => _outcome(l10n, theme, state),
                  },
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _progress(
    AppLocalizations l10n,
    ThemeData theme, {
    required String phase,
    required FullBackupJobStatus? status,
    required bool isExport,
    required bool cancellable,
  }) {
    final total = status?.total ?? 0;
    final done = status?.done ?? 0;
    final value = total > 0 ? (done / total).clamp(0.0, 1.0) : null;
    return [
      Text(phase, style: theme.textTheme.titleMedium),
      const SizedBox(height: 12),
      LinearProgressIndicator(value: value),
      const SizedBox(height: 8),
      if (total > 0)
        Text(
          l10n.backupFullProgressBytes(
            done: formatBytes(done),
            total: formatBytes(total),
          ),
          style: theme.textTheme.bodySmall,
        ),
      const SizedBox(height: 24),
      Text(l10n.backupFullJobBackgroundHint, style: theme.textTheme.bodyMedium),
      const SizedBox(height: 24),
      if (cancellable && _confirmingCancel)
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isExport
                  ? l10n.backupFullJobCancelConfirmExport
                  : l10n.backupFullJobCancelConfirmRestore,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => setState(() => _confirmingCancel = false),
                  child: Text(l10n.backupFullJobKeepGoing),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  ),
                  onPressed: () {
                    setState(() => _confirmingCancel = false);
                    ref.read(fullBackupJobProvider.notifier).cancel();
                  },
                  child: Text(l10n.backupFullJobStop),
                ),
              ],
            ),
          ],
        )
      else if (cancellable)
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton(
            onPressed: () => setState(() => _confirmingCancel = true),
            child: Text(l10n.commonCancel),
          ),
        ),
    ];
  }

  List<Widget> _outcome(
    AppLocalizations l10n,
    ThemeData theme,
    FullBackupJobState state,
  ) {
    final status = state.status;
    final notifier = ref.read(fullBackupJobProvider.notifier);
    final isExport = state.kind == FullBackupJobKind.export;

    Widget line(String text, {IconData? icon, Color? color}) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, color: color ?? theme.colorScheme.primary),
            const SizedBox(width: 12),
          ],
          Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
        ],
      ),
    );

    Widget button(String label, VoidCallback onPressed) => Align(
      alignment: Alignment.centerRight,
      child: FilledButton(onPressed: onPressed, child: Text(label)),
    );

    switch (status.lifecycle) {
      case FullBackupJobLifecycle.done when isExport:
        return [
          line(
            l10n.backupFullExported(size: formatBytes(status.bytes)),
            icon: Icons.check_circle_outline,
          ),
          if (status.skippedFiles > 0)
            line(
              l10n.backupFullExportedWithSkipped(count: status.skippedFiles),
              icon: Icons.warning_amber_rounded,
              color: theme.colorScheme.error,
            ),
          if (!status.renamed)
            line(
              l10n.backupFullJobRenameFailed,
              icon: Icons.warning_amber_rounded,
              color: theme.colorScheme.error,
            ),
          const SizedBox(height: 12),
          button(l10n.backupFullJobDone, notifier.dismiss),
        ];
      case FullBackupJobLifecycle.done:
        return [
          Text(l10n.backupFullRestartTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          Text(l10n.backupFullRestartBody),
          const SizedBox(height: 24),
          button(l10n.backupFullRestartButton, notifier.exitApp),
        ];
      case FullBackupJobLifecycle.cancelled:
        return [
          line(l10n.backupFullCancelled, icon: Icons.block_outlined),
          const SizedBox(height: 12),
          button(l10n.backupFullJobClose, notifier.dismiss),
        ];
      case FullBackupJobLifecycle.failed:
        final details = status.error ?? '';
        return [
          line(
            isExport
                ? l10n.backupFullFailed(details: details)
                : l10n.backupFullRestoreFailed(details: details),
            icon: Icons.error_outline,
            color: theme.colorScheme.error,
          ),
          const SizedBox(height: 12),
          button(l10n.backupFullJobClose, notifier.dismiss),
        ];
      case FullBackupJobLifecycle.none:
      case FullBackupJobLifecycle.running:
      case FullBackupJobLifecycle.paused:
        return const [];
    }
  }

  String _phaseText(AppLocalizations l10n, FullBackupJobStatus status) {
    if (status.lifecycle == FullBackupJobLifecycle.paused) {
      final error = status.error;
      return error == null
          ? l10n.backupFullJobPhaseResuming
          : l10n.backupFullJobPaused(details: error);
    }
    return switch (status.phase) {
      'writing' => l10n.backupFullJobPhaseWriting,
      'checking' => l10n.backupFullJobPhaseChecking,
      'extracting' => l10n.backupFullJobPhaseExtracting,
      'finishing' => l10n.backupFullJobPhaseFinishing,
      _ => l10n.backupFullProgressPreparing,
    };
  }
}
