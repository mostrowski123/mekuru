import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/backup/presentation/providers/backup_providers.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/utils/format_bytes.dart';

/// Blocks the backup screen while a full backup exports or a restore stages,
/// showing bytes done and offering Cancel.
///
/// A plain overlay driven by notifier state rather than a dialog route: it
/// appears and disappears exactly with `isWorking`, with no Navigator to
/// race against the confirmation dialogs that follow.
class FullBackupProgressOverlay extends ConsumerWidget {
  const FullBackupProgressOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(fullBackupNotifierProvider);
    if (!state.isWorking) return const SizedBox.shrink();

    final l10n = context.l10n;
    final theme = Theme.of(context);
    final title = switch (state.phase) {
      FullBackupPhase.measuring ||
      FullBackupPhase.exporting => l10n.backupFullProgressExporting,
      FullBackupPhase.extracting => l10n.backupFullProgressExtracting,
      FullBackupPhase.finishing => l10n.backupFullProgressFinishing,
      FullBackupPhase.preparing ||
      FullBackupPhase.idle => l10n.backupFullProgressPreparing,
    };
    final hasTotal = state.total > 0;

    return Stack(
      fit: StackFit.expand,
      children: [
        const ModalBarrier(dismissible: false, color: Colors.black54),
        Center(
          child: Card(
            margin: const EdgeInsets.all(32),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: hasTotal
                        ? (state.done / state.total).clamp(0.0, 1.0)
                        : null,
                  ),
                  if (hasTotal) ...[
                    const SizedBox(height: 8),
                    Text(
                      l10n.backupFullProgressBytes(
                        done: formatBytes(state.done),
                        total: formatBytes(state.total),
                      ),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => ref
                          .read(fullBackupNotifierProvider.notifier)
                          .cancel(),
                      child: Text(l10n.commonCancel),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
