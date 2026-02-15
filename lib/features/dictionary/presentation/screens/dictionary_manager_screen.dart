import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';

/// Screen for managing imported Yomitan dictionaries.
class DictionaryManagerScreen extends ConsumerWidget {
  const DictionaryManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dictionariesAsync = ref.watch(dictionariesProvider);
    final importState = ref.watch(dictionaryImportProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dictionary Manager'),
        actions: [
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
                  return _buildEmptyState();
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: dictionaries.length,
                  itemBuilder: (context, index) =>
                      _buildDictionaryTile(context, ref, dictionaries[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBanner(DictionaryImportState state) {
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
              Text(
                'Importing... ${state.processedEntries}/${state.totalEntries}',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: state.progress),
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
            'Tap + to import a Yomitan dictionary',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildDictionaryTile(
    BuildContext context,
    WidgetRef ref,
    dynamic dict,
  ) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: const Icon(Icons.menu_book),
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
