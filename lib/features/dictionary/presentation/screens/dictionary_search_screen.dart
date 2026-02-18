import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_query_service.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/features/dictionary/presentation/screens/dictionary_manager_screen.dart';
import 'package:mekuru/features/dictionary/presentation/widgets/kanji_stroke_order.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/shared/widgets/dictionary_entry_card.dart';

/// Dictionary search screen with live fuzzy search.
///
/// Supports kanji, hiragana, katakana, and romaji input.
/// When [initialQuery] is provided (e.g., from tapping a word in a definition),
/// the search is triggered immediately and the screen shows a back button.
class DictionarySearchScreen extends ConsumerStatefulWidget {
  const DictionarySearchScreen({super.key, this.initialQuery});

  final String? initialQuery;

  @override
  DictionarySearchScreenState createState() =>
      DictionarySearchScreenState();
}

class DictionarySearchScreenState
    extends ConsumerState<DictionarySearchScreen> {
  static final _latinPattern = RegExp(r'[a-zA-Z]');

  late final TextEditingController _controller;
  late final FocusNode _searchFocusNode;
  Timer? _debounce;
  List<DictionaryEntryWithSource>? _results;
  bool _isSearching = false;
  String _lastQuery = '';

  /// Request focus on the search field (e.g. when the tab becomes visible).
  ///
  /// A short delay ensures the platform input connection is ready,
  /// which is necessary for the soft keyboard to appear on cold start.
  Future<void> requestSearchFocus() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (mounted) {
      _searchFocusNode.requestFocus();
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery ?? '');
    _searchFocusNode = FocusNode();
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
    _searchFocusNode.dispose();
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
      var results = await queryService.fuzzySearchWithSource(term);

      // Apply Roman letter filter if enabled
      if (ref.read(filterRomanLettersProvider)) {
        results = results
            .where((r) => !_latinPattern.hasMatch(r.entry.expression))
            .toList();
      }

      // Only update if this is still the latest query
      if (mounted && term == _lastQuery) {
        if (results.isNotEmpty) {
          ref.read(searchHistoryProvider.notifier).addSearch(term);
        }
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

    // Re-search when Roman letter filter changes
    ref.listen(filterRomanLettersProvider, (_, _) {
      if (_lastQuery.isNotEmpty) {
        _performSearch(_lastQuery);
      }
    });

    // Re-search when dictionaries are enabled/disabled/added/removed
    ref.listen(dictionariesProvider, (_, _) {
      if (_lastQuery.isNotEmpty) {
        _performSearch(_lastQuery);
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dictionary'),
        actions: [
          IconButton(
            icon: const Icon(Icons.library_books_outlined),
            tooltip: 'Manage Dictionaries',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const DictionaryManagerScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _controller,
              focusNode: _searchFocusNode,
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
    final query = _lastQuery;
    final isSingleKanji = query.length == 1 && _isCjk(query.codeUnitAt(0));

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: results.length + (isSingleKanji ? 1 : 0),
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        // Show stroke order as the first item for single-kanji searches
        if (isSingleKanji && index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Center(child: KanjiStrokeOrder(kanji: query)),
          );
        }
        final resultIndex = isSingleKanji ? index - 1 : index;
        final result = results[resultIndex];
        return _SearchResultWithPitchAccents(
          entry: result.entry,
          dictionaryName: result.dictionaryName,
          frequencyRank: result.frequencyRank,
          fontSize: fontSize,
          onWordTap: _navigateToWord,
        );
      },
    );
  }

  Widget _buildEmptySearchState(ThemeData theme) {
    final history = ref.watch(searchHistoryProvider);

    if (history.isEmpty) {
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

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(
            children: [
              Text(
                'Recent',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  ref.read(searchHistoryProvider.notifier).clearAll();
                },
                child: const Text('Clear all'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: history.length,
            itemBuilder: (context, index) {
              final term = history[index];
              return ListTile(
                leading: Icon(
                  Icons.history,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                title: Text(term),
                trailing: IconButton(
                  icon: Icon(
                    Icons.close,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  onPressed: () {
                    ref.read(searchHistoryProvider.notifier).removeSearch(term);
                  },
                ),
                onTap: () {
                  _controller.text = term;
                  _controller.selection = TextSelection.fromPosition(
                    TextPosition(offset: term.length),
                  );
                  _performSearch(term);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

bool _isCjk(int codeUnit) {
  return (codeUnit >= 0x4E00 && codeUnit <= 0x9FFF) ||
      (codeUnit >= 0x3400 && codeUnit <= 0x4DBF);
}

/// Thin wrapper that fetches pitch accents and delegates to [DictionaryEntryCard].
class _SearchResultWithPitchAccents extends ConsumerStatefulWidget {
  const _SearchResultWithPitchAccents({
    required this.entry,
    required this.dictionaryName,
    required this.fontSize,
    required this.onWordTap,
    this.frequencyRank,
  });

  final DictionaryEntry entry;
  final String dictionaryName;
  final int? frequencyRank;
  final double fontSize;
  final void Function(String word) onWordTap;

  @override
  ConsumerState<_SearchResultWithPitchAccents> createState() =>
      _SearchResultWithPitchAccentsState();
}

class _SearchResultWithPitchAccentsState
    extends ConsumerState<_SearchResultWithPitchAccents> {
  late Future<List<PitchAccentResult>> _pitchAccentsFuture;

  @override
  void initState() {
    super.initState();
    _pitchAccentsFuture = ref
        .read(dictionaryQueryServiceProvider)
        .searchPitchAccents(widget.entry.expression);
  }

  /// Filter pitch accents to match this entry's reading or expression,
  /// then deduplicate by (reading, downstepPosition).
  List<PitchAccentResult> _filterPitchAccents(
    List<PitchAccentResult> allPitchAccents,
  ) {
    if (allPitchAccents.isEmpty) return [];

    final filtered = allPitchAccents.where((p) {
      if (widget.entry.reading.isNotEmpty &&
          p.reading == widget.entry.reading) {
        return true;
      }
      if (p.reading == widget.entry.expression) return true;
      if (p.reading.isEmpty) return true;
      return false;
    });

    final seen = <(String, int)>{};
    return filtered
        .where((p) => seen.add((p.reading, p.downstepPosition)))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PitchAccentResult>>(
      future: _pitchAccentsFuture,
      builder: (context, snapshot) {
        final filtered = _filterPitchAccents(snapshot.data ?? []);
        return DictionaryEntryCard(
          entry: widget.entry,
          dictionaryName: widget.dictionaryName,
          pitchAccents: filtered,
          fontSize: widget.fontSize,
          frequencyRank: widget.frequencyRank,
          onWordTap: widget.onWordTap,
        );
      },
    );
  }
}
