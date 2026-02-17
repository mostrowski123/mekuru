import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
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

  @override
  Widget build(BuildContext context) {
    final dictionariesAsync = ref.watch(dictionariesProvider);
    final importState = ref.watch(dictionaryImportProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dictionary Manager'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'Help',
            onPressed: () => _showHelpDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Import Dictionary',
            onPressed: importState.isImporting
                ? null
                : () => _importDictionary(context, ref),
          ),
        ],
      ),
      body: Column(
        children: [
          if (importState.isImporting) _buildProgressBanner(importState),
          if (importState.error != null)
            _buildErrorBanner(context, importState),
          if (importState.successMessage != null)
            _buildSuccessBanner(context, importState),
          Expanded(
            child: dictionariesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Error: $err')),
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
                  itemBuilder: (context, index) =>
                      _buildDictionaryTile(context, ref, displayList[index],
                          index: index),
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

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.book_outlined, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            'No dictionaries imported',
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
          SizedBox(height: 8),
          Text(
            'Tap + to import a Yomitan dictionary (.zip)\nor collection (.json)',
            style: TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildDictionaryTile(
    BuildContext context,
    WidgetRef ref,
    dynamic dict, {
    required int index,
  }) {
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
          'Imported ${_formatDate(dict.dateImported)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: dict.isEnabled,
              onChanged: (value) {
                ref
                    .read(dictionaryRepositoryProvider)
                    .toggleDictionary(dict.id, isEnabled: value);
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmDelete(context, ref, dict.id, dict.name),
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dictionary Manager'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Supported Formats',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Yomitan dictionary (.zip)\n'
                'Any dictionary that can be imported into Yomitan is '
                'supported. These are .zip files containing term bank '
                'JSON files.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Yomitan collection (.json)\n'
                'A Dexie database export containing multiple dictionaries '
                'in a single file. You can export this from Yomitan\'s '
                'settings under Backup.',
              ),
              const SizedBox(height: 16),
              Text(
                'Dictionary Order',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Drag dictionaries using the handle on the left to '
                'reorder them. The order here controls the order that '
                'definitions appear when you tap a word while reading.',
              ),
              const SizedBox(height: 16),
              Text(
                'Enabling & Disabling',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Use the toggle switch to enable or disable a dictionary. '
                'Disabled dictionaries are not searched when looking up words.',
              ),
              const SizedBox(height: 16),
              Text(
                'Finding Dictionaries',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(
                      text: 'Browse compatible dictionaries at ',
                    ),
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
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _importDictionary(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Dictionary'),
        content: Text(
          'Delete "$name" and all its entries?\nThis cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(dictionaryRepositoryProvider).deleteDictionary(id);
    }
  }
}
