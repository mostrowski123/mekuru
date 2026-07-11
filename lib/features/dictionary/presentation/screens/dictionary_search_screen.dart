import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_query_service.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/features/dictionary/presentation/screens/dictionary_manager_screen.dart';
import 'package:mekuru/features/dictionary/presentation/widgets/kanji_stroke_order.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/features/settings/presentation/screens/downloads_screen.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/widgets/grouped_dictionary_entry_card.dart';

/// Dictionary search screen with live fuzzy search.
///
/// Supports kanji, hiragana, katakana, and romaji input.
/// When [initialQuery] is provided (e.g., from tapping a word in a definition),
/// the search is triggered immediately and the screen shows a back button.
class DictionarySearchScreen extends ConsumerStatefulWidget {
  const DictionarySearchScreen({super.key, this.initialQuery});

  final String? initialQuery;

  @override
  DictionarySearchScreenState createState() => DictionarySearchScreenState();
}

class DictionarySearchScreenState extends ConsumerState<DictionarySearchScreen>
    with WidgetsBindingObserver {
  static final _latinPattern = RegExp(r'[a-zA-Z]');

  late final TextEditingController _controller;
  late final FocusNode _searchFocusNode;
  late final SearchHistoryNotifier _historyNotifier;
  Timer? _debounce;
  Timer? _historyDebounce;
  List<_GroupedSearchResultData>? _groupedResults;
  bool _isSearching = false;
  String _lastQuery = '';
  bool _autoCommitNextResult = false;

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
    WidgetsBinding.instance.addObserver(this);
    _controller = TextEditingController(text: widget.initialQuery ?? '');
    _searchFocusNode = FocusNode();
    // Cache so dispose() can save history without touching `ref` post-unmount.
    _historyNotifier = ref.read(searchHistoryProvider.notifier);
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      // Reader-initiated lookups (e.g., tapping a word in the EPUB) should
      // auto-save once results come back, since the tap itself is intent.
      _autoCommitNextResult = true;
      // Trigger initial search after build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _performSearch(widget.initialQuery!);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Riverpod forbids provider mutations inside lifecycle methods; defer the
    // commit so the addSearch state change happens after the tree finalizes.
    // Swallow errors: in tests the container may be disposed before the
    // microtask runs, and at app shutdown losing the last entry is harmless.
    if (_lastQuery.isNotEmpty && (_groupedResults?.isNotEmpty ?? false)) {
      final term = _lastQuery;
      final notifier = _historyNotifier;
      scheduleMicrotask(() {
        try {
          notifier.addSearch(term);
        } catch (_) {}
      });
    }
    _debounce?.cancel();
    _historyDebounce?.cancel();
    _controller.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    handleLifecycleStateChanged(state);
  }

  /// Lifecycle dispatcher split out so tests can drive transitions directly
  /// instead of routing through the binding (which fans out to every observer).
  @visibleForTesting
  void handleLifecycleStateChanged(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _commitToHistory();
      case AppLifecycleState.resumed:
        _restoreKeyboardIfFocused();
    }
  }

  /// On Android the focus state survives backgrounding but the soft keyboard
  /// does not. `requestFocus` is a no-op when focus is already held, so we
  /// drop focus and re-claim it to force a fresh input connection.
  void _restoreKeyboardIfFocused() {
    if (!_searchFocusNode.hasFocus) return;
    _searchFocusNode.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _historyDebounce?.cancel();
    // Any user-driven edit invalidates a pending reader-initiated auto-commit.
    _autoCommitNextResult = false;
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _groupedResults = null;
        _isSearching = false;
        _lastQuery = '';
      });
      return;
    }
    setState(() => _isSearching = true);
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch(trimmed);
    });
    // Pause-to-commit. If the 300ms search hasn't landed yet, _commitToHistory
    // no-ops cleanly; the tab-switch and lifecycle paths backstop that gap.
    _historyDebounce = Timer(const Duration(milliseconds: 1500), () {
      _commitToHistory();
    });
  }

  void _commitToHistory() {
    if (_lastQuery.isEmpty) return;
    if (_groupedResults?.isNotEmpty != true) return;
    _historyNotifier.addSearch(_lastQuery);
  }

  /// Public hook so the parent shell can commit when the user navigates away
  /// from the dictionary tab (the screen stays mounted inside IndexedStack).
  void commitHistoryIfNeeded() => _commitToHistory();

  void _clearSearch() {
    _historyDebounce?.cancel();
    _controller.clear();
    _onSearchChanged('');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _searchFocusNode.requestFocus();
      }
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

      final groupedResults = await _buildGroupedResults(
        results,
        queryService: queryService,
      );

      // Only update if this is still the latest query
      if (mounted && term == _lastQuery) {
        logUsage(
          'dictionary.search',
          attrs: {'result_count': results.length, 'query_length': term.length},
        );
        countUsage(
          'lookup.performed',
          attrs: {
            'source': 'search',
            'result': results.isEmpty ? 'miss' : 'hit',
          },
        );
        if (_autoCommitNextResult && results.isNotEmpty) {
          _autoCommitNextResult = false;
          _historyNotifier.addSearch(_lastQuery);
        }
        setState(() {
          _groupedResults = groupedResults;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted && term == _lastQuery) {
        setState(() {
          _groupedResults = const [];
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

  Future<List<_GroupedSearchResultData>> _buildGroupedResults(
    List<DictionaryEntryWithSource> results, {
    required DictionaryQueryService queryService,
  }) async {
    if (results.isEmpty) return const [];

    final groups = <(String, String), List<DictionaryEntryWithSource>>{};
    final groupOrder = <(String, String)>[];
    for (final result in results) {
      final key = (result.entry.expression, result.entry.reading);
      if (groups.containsKey(key)) {
        groups[key]!.add(result);
      } else {
        groups[key] = [result];
        groupOrder.add(key);
      }
    }

    final pitchAccentsByExpression = await queryService.searchPitchAccentsBatch(
      groupOrder.map((key) => key.$1),
    );

    return [
      for (final key in groupOrder)
        _GroupedSearchResultData(
          entries: groups[key]!,
          pitchAccents: _filterPitchAccentsForGroup(
            groups[key]!.first.entry,
            pitchAccentsByExpression[key.$1] ?? const [],
          ),
        ),
    ];
  }

  List<PitchAccentResult> _filterPitchAccentsForGroup(
    DictionaryEntry primaryEntry,
    List<PitchAccentResult> allPitchAccents,
  ) {
    if (allPitchAccents.isEmpty) return const [];

    final filtered = allPitchAccents.where((pitch) {
      if (primaryEntry.reading.isNotEmpty &&
          pitch.reading == primaryEntry.reading) {
        return true;
      }
      if (pitch.reading == primaryEntry.expression) return true;
      if (pitch.reading.isEmpty) return true;
      return false;
    });

    final seen = <(String, int)>{};
    return filtered
        .where((pitch) => seen.add((pitch.reading, pitch.downstepPosition)))
        .toList(growable: false);
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
        title: Text(context.l10n.navDictionary),
        actions: [
          IconButton(
            icon: const Icon(Icons.library_books_outlined),
            tooltip: context.l10n.commonManageDictionaries,
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
                hintText: context.l10n.dictionarySearchHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: _clearSearch,
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withAlpha(
                  120,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onChanged: _onSearchChanged,
              onSubmitted: (value) async {
                _debounce?.cancel();
                final trimmed = value.trim();
                if (trimmed.isEmpty) return;
                // If a search is pending or in-flight, run it now and wait so
                // _commitToHistory sees fresh results.
                if (_isSearching || trimmed != _lastQuery) {
                  await _performSearch(trimmed);
                }
                _commitToHistory();
              },
              textInputAction: TextInputAction.search,
            ),
          ),

          // Results area
          Expanded(
            child: hasDictionaries.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Text(
                  context.l10n.commonErrorWithDetails(details: err.toString()),
                ),
              ),
              data: (dictionaries) {
                if (dictionaries.isEmpty) {
                  return _buildNoDictionariesState(theme);
                }
                if (!dictionaries.any((dictionary) => dictionary.isEnabled)) {
                  return _buildNoEnabledDictionariesState(theme);
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
    final l10n = context.l10n;
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
              l10n.dictionaryNoDictionariesTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.dictionaryNoDictionariesSubtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withAlpha(150),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: _openDownloads,
                  icon: const Icon(Icons.download_outlined),
                  label: Text(l10n.dictionaryRecommendedStarterPack),
                ),
                OutlinedButton.icon(
                  onPressed: _openDictionaryManager,
                  icon: const Icon(Icons.library_books_outlined),
                  label: Text(l10n.commonManageDictionaries),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoEnabledDictionariesState(ThemeData theme) {
    final l10n = context.l10n;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.visibility_off_outlined,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant.withAlpha(100),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.dictionaryNoEnabledTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.dictionaryNoEnabledSubtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withAlpha(150),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: _openDictionaryManager,
                  icon: const Icon(Icons.toggle_on_outlined),
                  label: Text(l10n.dictionaryEnableDictionaries),
                ),
                OutlinedButton.icon(
                  onPressed: _openDownloads,
                  icon: const Icon(Icons.download_outlined),
                  label: Text(l10n.dictionaryStarterPack),
                ),
              ],
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

    if (_isSearching && _groupedResults == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final groupedResults = _groupedResults;
    if (groupedResults == null || groupedResults.isEmpty) {
      if (_isSearching) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(
        child: Text(
          context.l10n.dictionaryNoResultsFound,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final fontSize = ref.watch(lookupFontSizeProvider);
    final query = _lastQuery;
    final isSingleKanji = query.length == 1 && _isCjk(query.codeUnitAt(0));
    final slivers = <Widget>[
      if (isSingleKanji) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Center(child: KanjiStrokeOrder(kanji: query)),
          ),
        ),
        if (groupedResults.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Divider(
                height: 1,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
          ),
      ],
      for (var index = 0; index < groupedResults.length; index++) ...[
        SliverMainAxisGroup(
          key: ValueKey((
            groupedResults[index].entries.first.entry.expression,
            groupedResults[index].entries.first.entry.reading,
          )),
          slivers: [
            PinnedHeaderSliver(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border(
                    bottom: BorderSide(
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: 0.5,
                      ),
                      width: 0.5,
                    ),
                  ),
                ),
                child: GroupedDictionaryEntryHeader(
                  entries: groupedResults[index].entries,
                  pitchAccents: groupedResults[index].pitchAccents,
                  fontSize: fontSize,
                  onWordTap: _navigateToWord,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: GroupedDictionaryEntryBody(
                entries: groupedResults[index].entries,
                pitchAccents: groupedResults[index].pitchAccents,
                fontSize: fontSize,
                onWordTap: _navigateToWord,
              ),
            ),
          ],
        ),
        if (index < groupedResults.length - 1)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Divider(
                height: 1,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
          ),
      ],
      const SliverToBoxAdapter(child: SizedBox(height: 16)),
    ];

    return CustomScrollView(slivers: slivers);
  }

  Widget _buildEmptySearchState(ThemeData theme) {
    final l10n = context.l10n;
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
                l10n.dictionarySearchForAWord,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.dictionarySearchForAWordSubtitle,
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
                l10n.dictionaryRecent,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  ref.read(searchHistoryProvider.notifier).clearAll();
                },
                child: Text(l10n.commonClearAll),
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
                  // Re-promote the tapped term to the top of the MRU list.
                  _historyNotifier.addSearch(term);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _openDictionaryManager() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const DictionaryManagerScreen()));
  }

  void _openDownloads() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const DownloadsScreen()));
  }
}

bool _isCjk(int codeUnit) {
  return (codeUnit >= 0x4E00 && codeUnit <= 0x9FFF) ||
      (codeUnit >= 0x3400 && codeUnit <= 0x4DBF);
}

class _GroupedSearchResultData {
  const _GroupedSearchResultData({
    required this.entries,
    required this.pitchAccents,
  });

  final List<DictionaryEntryWithSource> entries;
  final List<PitchAccentResult> pitchAccents;
}
