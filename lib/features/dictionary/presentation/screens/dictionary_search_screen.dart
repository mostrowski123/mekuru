import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_query_service.dart';
import 'package:mekuru/features/dictionary/data/services/glossary_parser.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/features/dictionary/presentation/widgets/tappable_definition_text.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/shared/widgets/furigana_text.dart';

/// Dictionary search screen with live fuzzy search.
///
/// Supports kanji, hiragana, katakana, and romaji input.
/// When [initialQuery] is provided (e.g., from tapping a word in a definition),
/// the search is triggered immediately and the screen shows a back button.
class DictionarySearchScreen extends ConsumerStatefulWidget {
  const DictionarySearchScreen({super.key, this.initialQuery});

  final String? initialQuery;

  @override
  ConsumerState<DictionarySearchScreen> createState() =>
      _DictionarySearchScreenState();
}

class _DictionarySearchScreenState
    extends ConsumerState<DictionarySearchScreen> {
  late final TextEditingController _controller;
  Timer? _debounce;
  List<DictionaryEntryWithSource>? _results;
  bool _isSearching = false;
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery ?? '');
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      // Trigger initial search after build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _performSearch(widget.initialQuery!);
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _results = null;
        _isSearching = false;
        _lastQuery = '';
      });
      return;
    }
    setState(() => _isSearching = true);
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch(trimmed);
    });
  }

  Future<void> _performSearch(String term) async {
    if (!mounted) return;
    _lastQuery = term;
    setState(() => _isSearching = true);

    try {
      final queryService = ref.read(dictionaryQueryServiceProvider);
      final results = await queryService.fuzzySearchWithSource(term);
      // Only update if this is still the latest query
      if (mounted && term == _lastQuery) {
        setState(() {
          _results = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted && term == _lastQuery) {
        setState(() {
          _results = [];
          _isSearching = false;
        });
      }
    }
  }

  void _navigateToWord(String word) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DictionarySearchScreen(initialQuery: word),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDictionaries = ref.watch(dictionariesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dictionary'),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _controller,
              autofocus: false,
              decoration: InputDecoration(
                hintText: 'Search in kanji, kana, or romaji...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _controller.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest
                    .withAlpha(120),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
            ),
          ),

          // Results area
          Expanded(
            child: hasDictionaries.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Error: $err')),
              data: (dictionaries) {
                if (dictionaries.isEmpty) {
                  return _buildNoDictionariesState(theme);
                }
                return _buildResultsArea(theme);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoDictionariesState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.book_outlined,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant.withAlpha(100),
            ),
            const SizedBox(height: 16),
            Text(
              'No dictionaries imported',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Import dictionaries from Settings to start searching.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withAlpha(150),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsArea(ThemeData theme) {
    if (_controller.text.trim().isEmpty) {
      return _buildEmptySearchState(theme);
    }

    if (_isSearching && _results == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final results = _results;
    if (results == null || results.isEmpty) {
      if (_isSearching) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(
        child: Text(
          'No results found.',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final fontSize = ref.watch(lookupFontSizeProvider);

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: results.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final result = results[index];
        return _SearchResultItem(
          entry: result.entry,
          dictionaryName: result.dictionaryName,
          fontSize: fontSize,
          onWordTap: _navigateToWord,
        );
      },
    );
  }

  Widget _buildEmptySearchState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.translate,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant.withAlpha(80),
            ),
            const SizedBox(height: 16),
            Text(
              'Search for a word',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Type in kanji, hiragana, katakana, or romaji',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withAlpha(150),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Displays a single dictionary entry in search results.
class _SearchResultItem extends StatelessWidget {
  const _SearchResultItem({
    required this.entry,
    required this.dictionaryName,
    required this.fontSize,
    required this.onWordTap,
  });

  final DictionaryEntry entry;
  final String dictionaryName;
  final double fontSize;
  final void Function(String word) onWordTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fs = fontSize;
    final definitions = GlossaryParser.parse(entry.glossaries);

    final expressionStyle = TextStyle(
      fontSize: fs * 1.25,
      fontWeight: FontWeight.bold,
      color: theme.colorScheme.onSurface,
    );

    final furiganaStyle = TextStyle(
      fontSize: fs * 0.7,
      fontWeight: FontWeight.w400,
      color: theme.colorScheme.onSurface,
      height: 1.0,
    );

    final badgeStyle = TextStyle(
      fontSize: fs * 0.75,
      color: theme.colorScheme.onSurfaceVariant,
    );

    final definitionStyle = TextStyle(
      fontSize: fs,
      color: theme.colorScheme.onSurface,
    );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Expression + reading, dictionary badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FuriganaText(
                expression: entry.expression,
                reading: entry.reading,
                expressionStyle: expressionStyle,
                furiganaStyle: furiganaStyle,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    dictionaryName,
                    style: badgeStyle,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),

          // Row 2: Definitions (with tappable Japanese words)
          const SizedBox(height: 8),
          ...definitions.map(
            (def) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '- ',
                    style: TextStyle(
                      color: theme.colorScheme.outline,
                      fontSize: fs,
                    ),
                  ),
                  Expanded(
                    child: TappableDefinitionText(
                      text: def,
                      style: definitionStyle,
                      onWordTap: onWordTap,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
