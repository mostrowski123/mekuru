// ignore_for_file: discarded_futures
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/platform/capabilities.dart';
import 'package:mekuru/core/platform/full_backup_job_api.dart';
import 'package:mekuru/features/backup/presentation/providers/full_backup_job_provider.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/utils/format_bytes.dart';

/// What a full backup or restore that stopped with [code] did not do, and
/// what to do about it. The codes are the Android service's
/// (`FullBackupJobRunner`, `SafJobIo`, `JobStore`), the iOS job's
/// (`DartFullBackupJob`) and the boot-time apply's (`StagedFullRestore`). A
/// paused Android job records the name of what stopped it instead, and the
/// boot can record a runtime type: those, and any code this version does not
/// know, say only that it stopped, never the code.
String fullBackupFailureText(
  AppLocalizations l10n,
  FullBackupJobKind kind,
  String? code,
) {
  final restore = kind == FullBackupJobKind.restore;
  return switch (code) {
    // unsafe_archive while writing is a SecurityException: the folder's
    // access was taken away.
    'target_unavailable' ||
    'create_failed' ||
    'open_failed' ||
    'unsafe_archive' when !restore => l10n.backupFullFailedFolder,
    'partial_missing' => l10n.backupFullFailedFileMoved,
    'write_failed' || 'io_error' => l10n.backupFullFailedStorage,
    'source_missing' => l10n.backupFullFailedSource,
    'corrupt_archive' when restore => l10n.backupFullIncomplete,
    // An entry that would land outside the restore's folder.
    'unsafe_archive' => l10n.backupFullInvalid,
    'crash_loop' => l10n.backupFullFailedStuck,
    'incomplete_staging' => l10n.backupFullFailedStaging,
    _ => restore ? l10n.backupFullRestoreFailed : l10n.backupFullFailed,
  };
}

/// The snack bar on the first launch after a full restore that could not be
/// applied, for the [code] `StagedFullRestore` recorded.
String fullRestoreBootFailure(AppLocalizations l10n, String code) =>
    l10n.backupFullRestoreBootFailed(
      reason: fullBackupFailureText(l10n, FullBackupJobKind.restore, code),
    );

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
                        child: Text(switch ((
                          state.stage,
                          state.status.lifecycle,
                        )) {
                          (
                            FullBackupJobStage.terminal,
                            FullBackupJobLifecycle.done,
                          ) =>
                            isExport
                                ? l10n.backupFullJobExportDoneTitle
                                : l10n.backupFullJobRestoreDoneTitle,
                          // Failed or cancelled: no longer under way.
                          (FullBackupJobStage.terminal, _) =>
                            l10n.backupFullSectionTitle,
                          _ =>
                            isExport
                                ? l10n.backupFullJobExportTitle
                                : l10n.backupFullJobRestoreTitle,
                        }, style: theme.textTheme.headlineSmall),
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
      Text(switch (wording) {
        Wording.android => l10n.backupFullJobBackgroundHint,
        Wording.ios => l10n.backupFullJobBackgroundHintIos,
      }, style: theme.textTheme.bodyMedium),
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
          // iOS writes the zip inside the app; until it has been moved out,
          // offer the picker again (a cancelled picker must not cost the
          // whole export).
          if (defaultTargetPlatform == TargetPlatform.iOS &&
              status.location != null &&
              File(status.location!).existsSync())
            button(l10n.backupFullSaveButton, notifier.saveExportedZip),
          button(l10n.backupFullJobDone, notifier.dismiss),
        ];
      case FullBackupJobLifecycle.done:
        // iOS reloads in place; Android ends the process.
        final (title, body, action) = switch (wording) {
          Wording.android => (
            l10n.backupFullRestartTitle,
            l10n.backupFullRestartBody,
            l10n.backupFullRestartButton,
          ),
          Wording.ios => (
            l10n.backupFullReloadTitle,
            l10n.backupFullReloadBody,
            l10n.backupFullReloadButton,
          ),
        };
        return [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          Text(body),
          const SizedBox(height: 24),
          button(action, notifier.exitApp),
        ];
      case FullBackupJobLifecycle.cancelled:
        return [
          line(l10n.backupFullCancelled, icon: Icons.block_outlined),
          const SizedBox(height: 12),
          button(l10n.backupFullJobClose, notifier.dismiss),
        ];
      case FullBackupJobLifecycle.failed:
        return [
          line(
            fullBackupFailureText(l10n, state.kind, status.error),
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
          : l10n.backupFullJobPaused(
              reason: fullBackupFailureText(l10n, status.kind, error),
            );
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
