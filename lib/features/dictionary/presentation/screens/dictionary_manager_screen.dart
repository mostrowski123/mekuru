import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/backup/data/models/pending_dictionary_restore.dart';
import 'package:mekuru/features/backup/presentation/providers/backup_providers.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/features/settings/presentation/providers/jmdict_providers.dart';
import 'package:mekuru/features/settings/presentation/providers/jpdb_freq_providers.dart';
import 'package:mekuru/features/settings/presentation/providers/kanjidic_providers.dart';
import 'package:mekuru/features/settings/presentation/screens/downloads_screen.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/utils/haptics.dart';
import 'package:url_launcher/url_launcher.dart';

/// Screen for managing imported Yomitan dictionaries.
class DictionaryManagerScreen extends ConsumerStatefulWidget {
  const DictionaryManagerScreen({super.key});

  @override
  ConsumerState<DictionaryManagerScreen> createState() =>
      _DictionaryManagerScreenState();
}

class _DictionaryManagerScreenState
    extends ConsumerState<DictionaryManagerScreen> {
  /// Holds the reordered list while the async DB write is in flight.
  /// When null, the reactive stream data is used directly.
  List<dynamic>? _localOrder;
  bool _isApplyingPendingRestore = false;

  /// Dictionary IDs with a delete operation in flight. Used to swap the
  /// trash icon for a progress indicator and disable row controls.
  final Set<int> _deleting = <int>{};

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dictionariesAsync = ref.watch(dictionariesProvider);
    final importState = ref.watch(dictionaryImportProvider);
    final pendingRestoreAsync = ref.watch(
      pendingDictionaryRestorePreviewProvider,
    );
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.dictionaryManagerTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: l10n.commonHelp,
            onPressed: () => _showHelpDialog(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: importState.isImporting
            ? null
            : () => _importDictionary(context, ref),
        tooltip: l10n.dictionaryManagerImportTooltip,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          if (importState.isImporting) _buildProgressBanner(importState),
          if (importState.error != null)
            _buildErrorBanner(context, importState),
          if (importState.successMessage != null)
            _buildSuccessBanner(context, importState),
          _buildPendingRestoreCard(pendingRestoreAsync),
          Expanded(
            child: dictionariesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Text(l10n.commonErrorWithDetails(details: '$err')),
              ),
              data: (dictionaries) {
                if (dictionaries.isEmpty) {
                  _localOrder = null;
                  return _buildEmptyState();
                }
                final displayList = _localOrder ?? dictionaries;
                return ReorderableListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: displayList.length,
                  onReorder: (oldIndex, newIndex) {
                    if (oldIndex < newIndex) newIndex -= 1;
                    final reordered = List.of(displayList);
                    final item = reordered.removeAt(oldIndex);
                    reordered.insert(newIndex, item);
                    setState(() => _localOrder = reordered);
                    ref
                        .read(dictionaryRepositoryProvider)
                        .reorderDictionaries(
                          reordered.map((d) => d.id as int).toList(),
                        )
                        .then((_) {
                          if (mounted) {
                            setState(() => _localOrder = null);
                          }
                        });
                  },
                  itemBuilder: (context, index) => _buildDictionaryTile(
                    context,
                    ref,
                    displayList[index],
                    index: index,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBanner(DictionaryImportState state) {
    final hasCollectionProgress = state.dictionariesTotal > 0;
    final label = hasCollectionProgress
        ? 'Importing ${state.currentDictionary ?? ""}... '
              '(${state.dictionariesProcessed + 1}/${state.dictionariesTotal} dictionaries)'
        : state.currentDictionary != null
        ? '${state.currentDictionary}...'
        : 'Importing... ${state.processedEntries}/${state.totalEntries}';

    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.blue.withValues(alpha: 0.1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: state.progress),
          if (state.totalEntries > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${state.processedEntries}/${state.totalEntries} entries',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context, DictionaryImportState state) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              state.error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessBanner(
    BuildContext context,
    DictionaryImportState state,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.green.withValues(alpha: 0.1),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, color: Colors.green),
          const SizedBox(width: 8),
          Expanded(child: Text(state.successMessage!)),
        ],
      ),
    );
  }

  Widget _buildPendingRestoreCard(
    AsyncValue<PendingDictionaryRestorePreview?> pendingRestoreAsync,
  ) {
    return pendingRestoreAsync.when(
      data: (preview) {
        if (preview == null) return const SizedBox.shrink();

        final l10n = context.l10n;
        final theme = Theme.of(context);
        final canApply = preview.canApply && !_isApplyingPendingRestore;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Card(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.settings_backup_restore,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.dictionaryManagerPendingBackupTitle,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              l10n.dictionaryManagerPendingBackupBody,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.dictionaryManagerPendingBackupMatching(
                      count: preview.matchingCount,
                    ),
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.dictionaryManagerPendingBackupMissing(
                      count: preview.missingCount,
                    ),
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  if (preview.canApply)
                    FilledButton.icon(
                      onPressed: canApply ? _confirmApplyPendingRestore : null,
                      icon: _isApplyingPendingRestore
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.done_all),
                      label: Text(
                        l10n.dictionaryManagerPendingBackupApplyButton,
                      ),
                    )
                  else
                    Text(
                      l10n.dictionaryManagerPendingBackupNoMatches,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  Widget _buildEmptyState() {
    final l10n = context.l10n;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.book_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            l10n.dictionaryNoDictionariesTitle,
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.dictionaryManagerEmptySubtitle,
            style: TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.download),
            label: Text(l10n.dictionaryManagerBrowseDownloads),
            onPressed: () {
              AppHaptics.light();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DownloadsScreen()),
              );
            },
          ),
          const SizedBox(height: 4),
          Text(
            l10n.dictionaryManagerBrowseDownloadsCaption,
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmApplyPendingRestore() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.dictionaryManagerPendingBackupWarningTitle),
        content: Text(l10n.dictionaryManagerPendingBackupWarningBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.dictionaryManagerPendingBackupApplyButton),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _applyPendingRestore();
    }
  }

  Future<void> _applyPendingRestore() async {
    if (_isApplyingPendingRestore) return;

    setState(() {
      _isApplyingPendingRestore = true;
      _localOrder = null;
    });

    try {
      final result = await ref
          .read(pendingDictionaryRestoreServiceProvider)
          .applyPendingRestore(ref.read(dictionaryRepositoryProvider));

      ref.invalidate(pendingDictionaryRestorePreviewProvider);

      if (!mounted) return;

      if (result.appliedCount == 0) {
        _showMessage(
          context.l10n.dictionaryManagerPendingBackupNoMatches,
          isError: true,
        );
      } else {
        _showMessage(
          context.l10n.dictionaryManagerPendingBackupApplied(
            applied: result.appliedCount,
            missing: result.missingCount,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      _showMessage(
        context.l10n.commonErrorWithDetails(details: '$e'),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _isApplyingPendingRestore = false);
      }
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Widget _buildDictionaryTile(
    BuildContext context,
    WidgetRef ref,
    dynamic dict, {
    required int index,
  }) {
    final l10n = context.l10n;

    final isDeleting = _deleting.contains(dict.id);

    return Card(
      key: ValueKey(dict.id),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: ReorderableDragStartListener(
          index: index,
          child: const Icon(Icons.drag_handle),
        ),
        title: Text(dict.name),
        subtitle: Text(
          l10n.dictionaryManagerImportedOn(
            date: _formatDate(dict.dateImported),
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: dict.isEnabled,
              onChanged: isDeleting
                  ? null
                  : (value) {
                      ref
                          .read(dictionaryRepositoryProvider)
                          .toggleDictionary(dict.id, isEnabled: value);
                    },
            ),
            if (isDeleting)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () =>
                    _confirmDelete(context, ref, dict.id, dict.name),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  void _showHelpDialog(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.dictionaryManagerTitle),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.dictionaryManagerSupportedFormatsTitle,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Text(l10n.dictionaryManagerSupportedFormatsYomitan),
              const SizedBox(height: 12),
              Text(l10n.dictionaryManagerSupportedFormatsCollection),
              const SizedBox(height: 16),
              Text(
                l10n.dictionaryManagerOrderTitle,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Text(l10n.dictionaryManagerOrderBody),
              const SizedBox(height: 16),
              Text(
                l10n.dictionaryManagerEnablingTitle,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Text(l10n.dictionaryManagerEnablingBody),
              const SizedBox(height: 16),
              Text(
                l10n.dictionaryManagerFindingTitle,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: l10n.dictionaryManagerFindingPrefix),
                    TextSpan(
                      text: 'yomitan.wiki/dictionaries',
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        decoration: TextDecoration.underline,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () => launchUrl(
                          Uri.parse('https://yomitan.wiki/dictionaries/'),
                          mode: LaunchMode.externalApplication,
                        ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonOk),
          ),
        ],
      ),
    );
  }

  Future<void> _importDictionary(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip', 'json'],
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return;

    final filePath = result.files.single.path;
    if (filePath == null) return;

    ref.read(dictionaryImportProvider.notifier).importDictionary(filePath);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    int id,
    String name,
  ) async {
    final l10n = context.l10n;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.dictionaryManagerDeleteTitle),
        content: Text(l10n.dictionaryManagerDeleteBody(name: name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (mounted) setState(() => _deleting.add(id));
      try {
        await ref.read(dictionaryRepositoryProvider).deleteDictionary(id);
        // Refresh download status so the downloads page reflects the deletion.
        ref.read(jmdictProvider.notifier).checkStatus();
        ref.read(kanjidicProvider.notifier).checkStatus();
        ref.read(jpdbFreqProvider.notifier).checkStatus();
      } finally {
        if (mounted) setState(() => _deleting.remove(id));
      }
    }
  }
}
