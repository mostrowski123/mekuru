import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/services/glossary_parser.dart';
import 'package:mekuru/features/vocabulary/presentation/providers/vocabulary_providers.dart';

class VocabularyScreen extends ConsumerStatefulWidget {
  const VocabularyScreen({super.key});

  @override
  ConsumerState<VocabularyScreen> createState() => _VocabularyScreenState();
}

class _VocabularyScreenState extends ConsumerState<VocabularyScreen> {
  bool _isSelectionMode = false;
  final Set<int> _selectedIds = {};

  void _enterSelectionMode() {
    setState(() {
      _isSelectionMode = true;
      _selectedIds.clear();
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelection(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll(List<SavedWord> words) {
    setState(() {
      _selectedIds.addAll(words.map((w) => w.id));
    });
  }

  void _deselectAll() {
    setState(() {
      _selectedIds.clear();
    });
  }

  void _exportSelected() {
    if (_selectedIds.isEmpty) return;
    ref.read(exportVocabularyProvider)(selectedIds: _selectedIds);
  }

  @override
  Widget build(BuildContext context) {
    final wordsAsync = ref.watch(vocabularyListProvider);

    return Scaffold(
      appBar: _isSelectionMode
          ? _buildSelectionAppBar(wordsAsync)
          : _buildNormalAppBar(),
      body: wordsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (words) {
          if (words.isEmpty) {
            return const Center(child: Text('No saved words yet.'));
          }
          return ListView.separated(
            itemCount: words.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final word = words[index];
              return _VocabularyItem(
                word: word,
                isSelectionMode: _isSelectionMode,
                isSelected: _selectedIds.contains(word.id),
                onToggleSelection: () => _toggleSelection(word.id),
              );
            },
          );
        },
      ),
    );
  }

  AppBar _buildNormalAppBar() {
    return AppBar(
      title: const Text('Vocabulary'),
      actions: [
        IconButton(
          icon: const Icon(Icons.share),
          tooltip: 'Export CSV',
          onPressed: _enterSelectionMode,
        ),
      ],
    );
  }

  AppBar _buildSelectionAppBar(AsyncValue<List<SavedWord>> wordsAsync) {
    final allWords = wordsAsync.asData?.value ?? [];
    final allSelected =
        allWords.isNotEmpty && _selectedIds.length == allWords.length;

    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _exitSelectionMode,
      ),
      title: Text('${_selectedIds.length} selected'),
      actions: [
        IconButton(
          icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
          tooltip: allSelected ? 'Deselect all' : 'Select all',
          onPressed: () {
            if (allSelected) {
              _deselectAll();
            } else {
              _selectAll(allWords);
            }
          },
        ),
        IconButton(
          icon: const Icon(Icons.share),
          tooltip: 'Export selected',
          onPressed: _selectedIds.isEmpty ? null : _exportSelected,
        ),
      ],
    );
  }
}

class _VocabularyItem extends ConsumerWidget {
  const _VocabularyItem({
    required this.word,
    required this.isSelectionMode,
    required this.isSelected,
    required this.onToggleSelection,
  });

  final SavedWord word;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback onToggleSelection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final definitions = GlossaryParser.parse(word.glossaries);

    final firstDefinition = definitions.isNotEmpty
        ? definitions.first
        : 'No definition';

    final tile = ExpansionTile(
      leading: isSelectionMode
          ? Checkbox(
              value: isSelected,
              onChanged: (_) => onToggleSelection(),
            )
          : null,
      title: Text(word.expression),
      subtitle: Text(
        word.reading.isNotEmpty && word.reading != word.expression
            ? '${word.reading} - $firstDefinition'
            : firstDefinition,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (definitions.length > 1)
                ...definitions.skip(1).map((d) => Text('- $d')),
              const SizedBox(height: 8),
              if (word.sentenceContext.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Context:',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(word.sentenceContext),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                'Added: ${_formatDate(word.dateAdded)}',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.outline,
                ),
                textAlign: TextAlign.right,
              ),
            ],
          ),
        ),
      ],
    );

    if (isSelectionMode) {
      return InkWell(
        onTap: onToggleSelection,
        child: tile,
      );
    }

    return Dismissible(
      key: Key('vocab_${word.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) {
        ref.read(vocabularyRepositoryProvider).deleteWord(word.id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted "${word.expression}"'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () {
                // To implement undo, we'd need to re-add the word.
              },
            ),
          ),
        );
      },
      child: tile,
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
