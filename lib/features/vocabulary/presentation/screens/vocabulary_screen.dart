import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/services/glossary_parser.dart';
import 'package:mekuru/features/dictionary/presentation/screens/dictionary_search_screen.dart';
import 'package:mekuru/features/settings/presentation/screens/downloads_screen.dart';
import 'package:mekuru/features/vocabulary/presentation/providers/vocabulary_providers.dart';
import 'package:mekuru/features/vocabulary/presentation/utils/vocabulary_search.dart';

class VocabularyScreen extends ConsumerStatefulWidget {
  const VocabularyScreen({super.key});

  @override
  ConsumerState<VocabularyScreen> createState() => _VocabularyScreenState();
}

class _VocabularyScreenState extends ConsumerState<VocabularyScreen> {
  bool _isSelectionMode = false;
  final Set<int> _selectedIds = {};
  late final TextEditingController _searchController;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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

  void _setSearchQuery(String value) {
    setState(() {
      _searchQuery = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final wordsAsync = ref.watch(vocabularyListProvider);
    final visibleWords = wordsAsync.maybeWhen(
      data: (words) => filterVocabularyWords(words, _searchQuery),
      orElse: () => const <SavedWord>[],
    );

    return Scaffold(
      appBar: _isSelectionMode
          ? _buildSelectionAppBar(visibleWords)
          : _buildNormalAppBar(),
      body: wordsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (words) {
          if (words.isEmpty) {
            return _buildEmptyState(context);
          }
          final filteredWords = filterVocabularyWords(words, _searchQuery);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search saved words',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              _setSearchQuery('');
                            },
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    filled: true,
                  ),
                  onChanged: _setSearchQuery,
                ),
              ),
              Expanded(
                child: filteredWords.isEmpty
                    ? _buildNoMatchesState(context)
                    : ListView.separated(
                        itemCount: filteredWords.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final word = filteredWords[index];
                          return _VocabularyItem(
                            word: word,
                            isSelectionMode: _isSelectionMode,
                            isSelected: _selectedIds.contains(word.id),
                            onToggleSelection: () => _toggleSelection(word.id),
                          );
                        },
                      ),
              ),
            ],
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
          icon: const Icon(Icons.save_alt),
          tooltip: 'Export CSV',
          onPressed: _enterSelectionMode,
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bookmark_outline,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant.withAlpha(100),
            ),
            const SizedBox(height: 16),
            Text('No saved words yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Save words from dictionary searches or while reading, and they will show up here with context.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const DictionarySearchScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.search),
                  label: const Text('Open Dictionary'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const DownloadsScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Get Dictionaries'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoMatchesState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant.withAlpha(110),
            ),
            const SizedBox(height: 12),
            Text(
              'No matches for "$_searchQuery"',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Try the expression, reading, or part of a definition.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () {
                _searchController.clear();
                _setSearchQuery('');
              },
              child: const Text('Clear search'),
            ),
          ],
        ),
      ),
    );
  }

  AppBar _buildSelectionAppBar(List<SavedWord> visibleWords) {
    final allSelected =
        visibleWords.isNotEmpty &&
        visibleWords.every((word) => _selectedIds.contains(word.id));

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
              _selectAll(visibleWords);
            }
          },
        ),
        IconButton(
          icon: const Icon(Icons.save_alt),
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
          ? Checkbox(value: isSelected, onChanged: (_) => onToggleSelection())
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
      return InkWell(onTap: onToggleSelection, child: tile);
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
      onDismissed: (_) async {
        final repository = ref.read(vocabularyRepositoryProvider);
        await repository.deleteWord(word.id);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text('Deleted "${word.expression}"'),
              action: SnackBarAction(
                label: 'Undo',
                onPressed: () async {
                  await repository.restoreWord(word);
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
