import 'package:drift/drift.dart';
import 'package:fuzzy_bolt/fuzzy_bolt.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/services/romaji_converter.dart';
import 'package:mekuru/features/reader/data/services/deinflection.dart';

/// A dictionary entry paired with the name of the dictionary it came from.
class DictionaryEntryWithSource {
  static const int missingFrequencySortRank = 1 << 62;

  final DictionaryEntry entry;
  final String dictionaryName;
  final int? frequencyRank;

  const DictionaryEntryWithSource({
    required this.entry,
    required this.dictionaryName,
    this.frequencyRank,
  });

  /// Convert a nullable frequency into a sortable rank where missing
  /// frequencies are treated as the least frequent.
  static int sortFrequencyRank(int? rank) {
    return rank ?? missingFrequencySortRank;
  }

  /// Returns a qualitative label for the frequency rank.
  static String frequencyLabel(int? rank) {
    final resolvedRank = sortFrequencyRank(rank);
    if (resolvedRank <= 5000) return 'Very Common';
    if (resolvedRank <= 15000) return 'Common';
    if (resolvedRank <= 30000) return 'Uncommon';
    return 'Rare';
  }

  /// Copy with a different frequency rank.
  DictionaryEntryWithSource withFrequencyRank(int? rank) {
    return DictionaryEntryWithSource(
      entry: entry,
      dictionaryName: dictionaryName,
      frequencyRank: rank,
    );
  }
}

/// A pitch accent result with its source dictionary name.
class PitchAccentResult {
  final String reading;
  final int downstepPosition;
  final String dictionaryName;

  const PitchAccentResult({
    required this.reading,
    required this.downstepPosition,
    required this.dictionaryName,
  });
}

/// Cached dictionary metadata for avoiding repeated JOIN queries.
class _MetasCache {
  final Set<int> enabledIds;
  final Map<int, String> names;
  final Map<int, int> sortOrders;

  const _MetasCache({
    required this.enabledIds,
    required this.names,
    required this.sortOrders,
  });
}

/// Service for querying dictionary entries.
class DictionaryQueryService {
  final AppDatabase _db;
  _MetasCache? _metasCache;

  DictionaryQueryService(this._db);

  /// Invalidate the cached dictionary metadata. Call this when dictionaries
  /// are toggled, reordered, deleted, or imported.
  void invalidateMetasCache() {
    _metasCache = null;
  }

  /// Ensure the dictionary metadata cache is populated.
  Future<_MetasCache> _ensureMetasCached() async {
    if (_metasCache != null) return _metasCache!;

    final rows = await (_db.select(
      _db.dictionaryMetas,
    )..where((t) => t.isEnabled.equals(true))).get();

    final enabledIds = <int>{};
    final names = <int, String>{};
    final sortOrders = <int, int>{};

    for (final row in rows) {
      enabledIds.add(row.id);
      names[row.id] = row.name;
      sortOrders[row.id] = row.sortOrder;
    }

    _metasCache = _MetasCache(
      enabledIds: enabledIds,
      names: names,
      sortOrders: sortOrders,
    );
    return _metasCache!;
  }

  /// Sort entries by their dictionary's sort order using the cached metadata.
  void _sortBySortOrder(List<DictionaryEntry> entries, _MetasCache cache) {
    if (entries.length < 2) return;
    entries.sort((a, b) {
      final orderA = cache.sortOrders[a.dictionaryId] ?? 0;
      final orderB = cache.sortOrders[b.dictionaryId] ?? 0;
      return orderA.compareTo(orderB);
    });
  }

  int _exactMatchPriority(DictionaryEntry entry, Set<String> exactTerms) {
    if (exactTerms.contains(entry.expression)) return 0;
    if (exactTerms.contains(entry.reading)) return 1;
    return 2;
  }

  void _sortExactMatches(
    List<DictionaryEntry> entries,
    _MetasCache cache,
    Set<String> exactTerms,
  ) {
    if (entries.length < 2 || exactTerms.isEmpty) {
      _sortBySortOrder(entries, cache);
      return;
    }

    entries.sort((a, b) {
      final priorityA = _exactMatchPriority(a, exactTerms);
      final priorityB = _exactMatchPriority(b, exactTerms);
      if (priorityA != priorityB) {
        return priorityA.compareTo(priorityB);
      }

      final orderA = cache.sortOrders[a.dictionaryId] ?? 0;
      final orderB = cache.sortOrders[b.dictionaryId] ?? 0;
      return orderA.compareTo(orderB);
    });
  }

  /// Sort entries-with-source by their dictionary's sort order.
  void _sortWithSourceBySortOrder(
    List<DictionaryEntryWithSource> entries,
    _MetasCache cache,
  ) {
    if (entries.length < 2) return;
    entries.sort((a, b) {
      final orderA = cache.sortOrders[a.entry.dictionaryId] ?? 0;
      final orderB = cache.sortOrders[b.entry.dictionaryId] ?? 0;
      return orderA.compareTo(orderB);
    });
  }

  List<DictionaryEntryWithSource> _mapEntriesWithSource(
    List<DictionaryEntry> rows,
    _MetasCache cache,
  ) {
    final results = rows.map((entry) {
      return DictionaryEntryWithSource(
        entry: entry,
        dictionaryName: cache.names[entry.dictionaryId] ?? '',
      );
    }).toList();

    _sortWithSourceBySortOrder(results, cache);
    return results;
  }

  List<DictionaryEntryWithSource> _mapEntriesWithSourceUnsorted(
    List<DictionaryEntry> rows,
    _MetasCache cache,
  ) {
    return rows.map((entry) {
      return DictionaryEntryWithSource(
        entry: entry,
        dictionaryName: cache.names[entry.dictionaryId] ?? '',
      );
    }).toList();
  }

  Map<(String, String), int> _buildExactMatchPriorities(
    List<DictionaryEntryWithSource> results,
    Set<String> exactTerms,
  ) {
    if (results.isEmpty || exactTerms.isEmpty) return {};

    final priorities = <(String, String), int>{};
    for (final result in results) {
      final key = (result.entry.expression, result.entry.reading);
      final priority = _exactMatchPriority(result.entry, exactTerms);
      final existing = priorities[key];
      if (existing == null || priority < existing) {
        priorities[key] = priority;
      }
    }

    return priorities;
  }

  Future<List<DictionaryEntryWithSource>> _searchWithSourceNoFrequency(
    String term,
    _MetasCache cache,
  ) async {
    final query = _db.select(_db.dictionaryEntries)
      ..where(
        (t) =>
            (t.expression.equals(term) | t.reading.equals(term)) &
            t.dictionaryId.isIn(cache.enabledIds),
      );

    final rows = await query.get();
    return _mapEntriesWithSource(rows, cache);
  }

  Future<List<DictionaryEntryWithSource>> _searchMultipleWithSourceNoFrequency(
    List<String> terms,
    _MetasCache cache,
  ) async {
    if (terms.isEmpty) return [];

    final query = _db.select(_db.dictionaryEntries)
      ..where(
        (t) =>
            (t.expression.isIn(terms) | t.reading.isIn(terms)) &
            t.dictionaryId.isIn(cache.enabledIds),
      );

    final rows = await query.get();
    return _mapEntriesWithSource(rows, cache);
  }

  /// Search entries by exact expression match.
  /// Only returns results from enabled dictionaries, ordered by dictionary sort order.
  Future<List<DictionaryEntry>> searchByExpression(String expression) async {
    final cache = await _ensureMetasCached();
    if (cache.enabledIds.isEmpty) return [];

    final query = _db.select(_db.dictionaryEntries)
      ..where(
        (t) =>
            t.expression.equals(expression) &
            t.dictionaryId.isIn(cache.enabledIds),
      );

    final results = await query.get();
    _sortBySortOrder(results, cache);
    return results;
  }

  /// Search entries by reading (hiragana/katakana).
  /// Only returns results from enabled dictionaries, ordered by dictionary sort order.
  Future<List<DictionaryEntry>> searchByReading(String reading) async {
    final cache = await _ensureMetasCached();
    if (cache.enabledIds.isEmpty) return [];

    final query = _db.select(_db.dictionaryEntries)
      ..where(
        (t) =>
            t.reading.equals(reading) & t.dictionaryId.isIn(cache.enabledIds),
      );

    final results = await query.get();
    _sortBySortOrder(results, cache);
    return results;
  }

  /// Search entries by expression OR reading.
  /// Used for the lookup bottom sheet when we don't know
  /// if the selection is kanji or kana.
  /// Exact expression matches are prioritized before reading-only matches.
  /// Within each match type, results follow dictionary sort order.
  Future<List<DictionaryEntry>> search(String term) async {
    final cache = await _ensureMetasCached();
    if (cache.enabledIds.isEmpty) return [];

    final query = _db.select(_db.dictionaryEntries)
      ..where(
        (t) =>
            (t.expression.equals(term) | t.reading.equals(term)) &
            t.dictionaryId.isIn(cache.enabledIds),
      );

    final results = await query.get();
    _sortExactMatches(results, cache, {term});
    return results;
  }

  /// Returns `true` if [term] exists as an expression or reading in any
  /// enabled dictionary. Uses LIMIT 1 for efficiency — only checks existence,
  /// does not fetch full entry data.
  Future<bool> hasMatch(String term) async {
    final cache = await _ensureMetasCached();
    if (cache.enabledIds.isEmpty) return false;

    final query = _db.selectOnly(_db.dictionaryEntries)
      ..addColumns([_db.dictionaryEntries.id])
      ..where(
        (_db.dictionaryEntries.expression.equals(term) |
                _db.dictionaryEntries.reading.equals(term)) &
            _db.dictionaryEntries.dictionaryId.isIn(cache.enabledIds),
      )
      ..limit(1);

    final row = await query.getSingleOrNull();
    return row != null;
  }

  /// Search entries and include the dictionary name for each result.
  /// Exact expression matches are prioritized before reading-only matches.
  /// Within each match type, results are ordered by frequency rank (most
  /// common first), then by dictionary sort order as a tiebreaker.
  Future<List<DictionaryEntryWithSource>> searchWithSource(String term) async {
    final cache = await _ensureMetasCached();
    if (cache.enabledIds.isEmpty) return [];

    final results = await _searchWithSourceNoFrequency(term, cache);
    return _attachFrequencyRanks(results, exactTerms: {term});
  }

  /// Look up the best (lowest) frequency rank for a given expression.
  /// Queries all frequency dictionaries regardless of isEnabled flag.
  Future<int?> getFrequencyRank(
    String expression, [
    String reading = '',
  ]) async {
    final query = _db.selectOnly(_db.frequencies)
      ..addColumns([_db.frequencies.frequencyRank.min()])
      ..where(
        _db.frequencies.expression.equals(expression) |
            (reading.isNotEmpty
                ? _db.frequencies.reading.equals(reading)
                : const Constant(false)),
      );

    final result = await query.getSingleOrNull();
    return result?.read(_db.frequencies.frequencyRank.min());
  }

  /// Batch-query frequency ranks keyed by (expression, reading) pair.
  ///
  /// Lookup strategy per pair:
  /// 1. Prefer an exact (expression, reading) match in the Frequencies table.
  /// 2. Fall back to an exact surface-form rank for the result's expression
  ///    when the frequency source does not specify a reading.
  /// 3. If the searched term exactly matches the result's reading, allow an
  ///    exact surface-form rank for that searched kana term.
  ///
  /// Importantly, this does not borrow the best rank from a different reading
  /// of the same expression. For example, `私/わっし` must not inherit the
  /// frequency rank of `私/わたし`.
  Future<Map<(String, String), int>> _getFrequencyRanks(
    List<DictionaryEntryWithSource> results,
    Set<String> searchTerms,
  ) async {
    if (results.isEmpty) return {};

    final lookupExpressions = <String>{
      ...results.map((r) => r.entry.expression),
      ...searchTerms.where((term) => term.isNotEmpty),
    };
    if (lookupExpressions.isEmpty) return {};

    // Fetch ALL frequency rows for these expressions in batches.
    final allRows = <TypedResult>[];
    final exprList = lookupExpressions.toList();
    const batchSize = 200;

    for (var i = 0; i < exprList.length; i += batchSize) {
      final end = (i + batchSize < exprList.length)
          ? i + batchSize
          : exprList.length;
      final batch = exprList.sublist(i, end);

      final query = _db.selectOnly(_db.frequencies)
        ..addColumns([
          _db.frequencies.expression,
          _db.frequencies.reading,
          _db.frequencies.frequencyRank,
        ])
        ..where(_db.frequencies.expression.isIn(batch));

      allRows.addAll(await query.get());
    }

    // Build two lookup structures:
    // 1. (expression, reading) -> min rank for reading-specific entries
    // 2. expression -> min rank for surface-form-only entries
    final pairRanks = <(String, String), int>{};
    final surfaceRanks = <String, int>{};

    for (final row in allRows) {
      final expression = row.read(_db.frequencies.expression);
      final reading = row.read(_db.frequencies.reading);
      final frequencyRank = row.read(_db.frequencies.frequencyRank);
      if (expression == null || reading == null || frequencyRank == null) {
        continue;
      }

      if (reading.isEmpty) {
        final existingSurfaceRank = surfaceRanks[expression];
        if (existingSurfaceRank == null ||
            frequencyRank < existingSurfaceRank) {
          surfaceRanks[expression] = frequencyRank;
        }
        continue;
      }

      final key = (expression, reading);
      final existingPairRank = pairRanks[key];
      if (existingPairRank == null || frequencyRank < existingPairRank) {
        pairRanks[key] = frequencyRank;
      }
    }

    // For each unique (expression, reading) in results, prefer the
    // pair-specific rank. When that pair is missing, only fall back to an
    // exact surface-form rank for the same expression, or for the searched
    // reading itself when the user searched by kana.
    final resultPairs = results
        .map((r) => (r.entry.expression, r.entry.reading))
        .toSet();

    final ranks = <(String, String), int>{};
    for (final pair in resultPairs) {
      final pairRank = pairRanks[pair];
      if (pairRank != null) {
        ranks[pair] = pairRank;
        continue;
      }

      final expressionSurfaceRank = surfaceRanks[pair.$1];
      if (expressionSurfaceRank != null) {
        ranks[pair] = expressionSurfaceRank;
        continue;
      }

      if (pair.$2.isNotEmpty && searchTerms.contains(pair.$2)) {
        final readingSurfaceRank = surfaceRanks[pair.$2];
        if (readingSurfaceRank != null) {
          ranks[pair] = readingSurfaceRank;
        }
      }
    }

    return ranks;
  }

  /// Attach frequency ranks and group results by (expression, reading).
  ///
  /// Within each group, entries retain their original order (which is the
  /// dictionary sort_order from the SQL query). Groups are ordered by
  /// exact-match priority when provided, then by frequency rank (lowest
  /// rank first, with missing frequencies treated as least frequent).
  Future<List<DictionaryEntryWithSource>> _attachFrequencyRanks(
    List<DictionaryEntryWithSource> results, {
    Set<String>? exactTerms,
  }) async {
    if (results.isEmpty) return results;

    final ranks = await _getFrequencyRanks(
      results,
      exactTerms ?? const <String>{},
    );
    final matchPriorities = exactTerms == null || exactTerms.isEmpty
        ? null
        : _buildExactMatchPriorities(results, exactTerms);
    return _applyFrequencyRanks(
      results,
      ranks,
      matchPriorities: matchPriorities,
    );
  }

  /// Apply pre-fetched frequency ranks and group/sort results.
  List<DictionaryEntryWithSource> _applyFrequencyRanks(
    List<DictionaryEntryWithSource> results,
    Map<(String, String), int> ranks, {
    Map<(String, String), int>? matchPriorities,
  }) {
    if (results.isEmpty) return results;

    // Attach frequency ranks to each entry.
    final ranked = results.map((r) {
      final rank = ranks[(r.entry.expression, r.entry.reading)];
      return r.withFrequencyRank(rank);
    }).toList();

    // Group by (expression, reading), preserving insertion order within
    // each group (which is the SQL sort_order).
    final groups = <(String, String), List<DictionaryEntryWithSource>>{};
    final groupOrder = <(String, String), int>{};
    for (final r in ranked) {
      final key = (r.entry.expression, r.entry.reading);
      groupOrder.putIfAbsent(key, () => groupOrder.length);
      groups.putIfAbsent(key, () => []).add(r);
    }

    // Sort group keys by exact-match priority first, then by frequency rank
    // (lowest first, with missing frequencies sorted last), preserving
    // original order for ties.
    final sortedKeys = groups.keys.toList()
      ..sort((a, b) {
        final priorityA = matchPriorities?[a] ?? 0;
        final priorityB = matchPriorities?[b] ?? 0;
        if (priorityA != priorityB) {
          return priorityA.compareTo(priorityB);
        }

        final rankA = ranks[a];
        final rankB = ranks[b];
        final rankCompare = DictionaryEntryWithSource.sortFrequencyRank(
          rankA,
        ).compareTo(DictionaryEntryWithSource.sortFrequencyRank(rankB));
        if (rankCompare != 0) return rankCompare;
        return groupOrder[a]!.compareTo(groupOrder[b]!);
      });

    // Flatten groups back into a single list.
    return [for (final key in sortedKeys) ...groups[key]!];
  }

  /// Search entries matching any of [terms] (by expression or reading).
  /// Exact expression matches are prioritized before reading-only matches.
  /// Within each match type, results are ordered by frequency rank.
  /// Useful for searching multiple deinflected candidate forms at once.
  Future<List<DictionaryEntryWithSource>> searchMultipleWithSource(
    List<String> terms,
  ) async {
    if (terms.isEmpty) return [];

    final cache = await _ensureMetasCached();
    if (cache.enabledIds.isEmpty) return [];

    final results = await _searchMultipleWithSourceNoFrequency(terms, cache);
    return _attachFrequencyRanks(results, exactTerms: terms.toSet());
  }

  /// Prefix search: expression or reading starts with [term].
  /// Returns up to [limit] results from enabled dictionaries.
  Future<List<DictionaryEntryWithSource>> prefixSearchWithSource(
    String term, {
    int limit = 50,
  }) async {
    if (term.isEmpty) return [];

    final cache = await _ensureMetasCached();
    if (cache.enabledIds.isEmpty) return [];

    final pattern = '$term%';
    final query = _db.select(_db.dictionaryEntries)
      ..where(
        (t) =>
            (t.expression.like(pattern) | t.reading.like(pattern)) &
            t.dictionaryId.isIn(cache.enabledIds),
      )
      ..limit(limit);

    final rows = await query.get();
    final results = rows.map((entry) {
      return DictionaryEntryWithSource(
        entry: entry,
        dictionaryName: cache.names[entry.dictionaryId] ?? '',
      );
    }).toList();

    _sortWithSourceBySortOrder(results, cache);
    return results;
  }

  /// Fuzzy search combining exact match, fuzzy_bolt ranked matches,
  /// sub-component matches, and English definition search.
  ///
  /// For romaji input, converts to hiragana and searches by reading.
  /// For katakana input, also searches the hiragana equivalent.
  /// For kanji input, also decomposes into individual kanji for sub-matches.
  /// For Latin/English input, also searches glossary definitions.
  ///
  /// Results are ordered by relevance tier: exact matches first, then
  /// fuzzy-ranked matches (via fuzzy_bolt), then sub-component matches,
  /// then glossary matches. Within each tier, results are sorted by frequency
  /// rank (most common first). Fuzzy and glossary tiers preserve their
  /// match-quality ordering as a secondary signal.
  Future<List<DictionaryEntryWithSource>> fuzzySearchWithSource(
    String term,
  ) async {
    if (term.isEmpty) return [];

    final cache = await _ensureMetasCached();
    if (cache.enabledIds.isEmpty) return [];

    final seenIds = <int>{};

    // Collect results per tier so we can sort within tiers by frequency
    // while preserving the tier ordering.
    final exactResults = <DictionaryEntryWithSource>[];
    final fuzzyResults = <DictionaryEntryWithSource>[];
    final subComponentResults = <DictionaryEntryWithSource>[];
    final glossaryResults = <DictionaryEntryWithSource>[];
    final exactMatchTerms = <String>{};

    void addTo(
      List<DictionaryEntryWithSource> bucket,
      List<DictionaryEntryWithSource> newResults,
    ) {
      for (final r in newResults) {
        if (seenIds.add(r.entry.id)) {
          bucket.add(r);
        }
      }
    }

    // Build search terms based on input type
    final searchTerms = <String>[term];
    final isRomaji = RomajiConverter.isRomaji(term);

    if (isRomaji) {
      final hiragana = RomajiConverter.convert(term);
      if (hiragana.isNotEmpty) {
        searchTerms.add(hiragana);
      }
    }

    // If input contains katakana, also try the hiragana version
    final hiraganaVersion = RomajiConverter.katakanaToHiragana(term);
    if (hiraganaVersion != term && !searchTerms.contains(hiraganaVersion)) {
      searchTerms.add(hiraganaVersion);
    }

    // 1. Exact matches (highest priority — always on top)
    exactMatchTerms.addAll(searchTerms);
    for (final t in searchTerms) {
      addTo(exactResults, await _searchWithSourceNoFrequency(t, cache));
    }

    // 1b. Deinflected exact matches (same tier as exact).
    // Reverses conjugation to find base forms (e.g., 行って → 行く, 行う).
    final deinflectedCandidates = <String>{};
    for (final t in searchTerms) {
      deinflectedCandidates.addAll(deinflect(t));
    }
    deinflectedCandidates.removeAll(searchTerms);
    if (deinflectedCandidates.isNotEmpty) {
      exactMatchTerms.addAll(deinflectedCandidates);
      addTo(
        exactResults,
        await _searchMultipleWithSourceNoFrequency(
          deinflectedCandidates.toList(),
          cache,
        ),
      );
    }

    // 2. Fuzzy matches on expression/reading via fuzzy_bolt
    final prefixCandidates = await _fetchPrefixCandidates(
      searchTerms,
      limit: 100,
    );
    if (prefixCandidates.isNotEmpty) {
      for (final t in searchTerms) {
        final fuzzyMatches = await FuzzyBolt.search<DictionaryEntryWithSource>(
          prefixCandidates,
          t,
          selectors: [(e) => e.entry.expression, (e) => e.entry.reading],
          strictThreshold: 0.8,
          typeThreshold: 0.3,
          maxResults: 30,
          skipIsolate: true,
        );
        addTo(fuzzyResults, fuzzyMatches);
      }
    }

    // 3. Sub-component matches (individual kanji from original term)
    if (!isRomaji && term.length > 1) {
      final seen = <String>{};
      for (final rune in term.runes) {
        final char = String.fromCharCode(rune);
        if (_isKanji(char) && seen.add(char)) {
          addTo(
            subComponentResults,
            await _searchWithSourceNoFrequency(char, cache),
          );
        }
      }
    }

    // 4. English definition fuzzy search via fuzzy_bolt
    // Candidates are pre-filtered by SQL LIKE, so we use a lower threshold
    // to avoid dropping short-term matches (e.g. "run" in "to run").
    if (_hasLatinLetters(term)) {
      // Always include direct glossary substring matches first so exact
      // English lookups remain reliable even when fuzzy scoring thresholds
      // are too strict for short terms (e.g. "run").
      final glossaryData = await _fetchGlossaryDirectAndCandidates(
        term,
        cache,
        directLimit: 30,
        candidateLimit: 100,
      );
      addTo(glossaryResults, glossaryData.directMatches);

      if (glossaryData.fuzzyCandidates.isNotEmpty) {
        final fuzzyMatches = await FuzzyBolt.search<DictionaryEntryWithSource>(
          glossaryData.fuzzyCandidates,
          term,
          selectors: [(e) => e.entry.glossaries],
          strictThreshold: 0.7,
          typeThreshold: 0.3,
          maxResults: 30,
          skipIsolate: true,
        );
        addTo(glossaryResults, fuzzyMatches);
      }
    }

    // Fetch frequency ranks once for all tiers combined, then apply per tier.
    final allResults = [
      ...exactResults,
      ...fuzzyResults,
      ...subComponentResults,
      ...glossaryResults,
    ];
    final ranks = await _getFrequencyRanks(allResults, exactMatchTerms);

    return [
      ..._applyFrequencyRanks(
        exactResults,
        ranks,
        matchPriorities: _buildExactMatchPriorities(
          exactResults,
          exactMatchTerms,
        ),
      ),
      ..._applyFrequencyRanks(fuzzyResults, ranks),
      ..._applyFrequencyRanks(subComponentResults, ranks),
      ..._applyFrequencyRanks(glossaryResults, ranks),
    ];
  }

  Future<
    ({
      List<DictionaryEntryWithSource> directMatches,
      List<DictionaryEntryWithSource> fuzzyCandidates,
    })
  >
  _fetchGlossaryDirectAndCandidates(
    String term,
    _MetasCache cache, {
    int directLimit = 30,
    int candidateLimit = 100,
  }) async {
    if (term.isEmpty || cache.enabledIds.isEmpty) {
      return (
        directMatches: <DictionaryEntryWithSource>[],
        fuzzyCandidates: <DictionaryEntryWithSource>[],
      );
    }

    final fetchLimit = directLimit > candidateLimit
        ? directLimit
        : candidateLimit;
    if (fetchLimit <= 0) {
      return (
        directMatches: <DictionaryEntryWithSource>[],
        fuzzyCandidates: <DictionaryEntryWithSource>[],
      );
    }

    final pattern = '%$term%';
    final query = _db.select(_db.dictionaryEntries)
      ..where(
        (t) =>
            t.glossaries.like(pattern) & t.dictionaryId.isIn(cache.enabledIds),
      )
      ..limit(fetchLimit);

    final rows = await query.get();
    final allMatches = _mapEntriesWithSourceUnsorted(rows, cache);

    final directMatches = allMatches.take(directLimit).toList();
    _sortWithSourceBySortOrder(directMatches, cache);

    return (
      directMatches: directMatches,
      fuzzyCandidates: allMatches.take(candidateLimit).toList(),
    );
  }

  /// Search entries whose glossary text contains [term] (case-insensitive).
  ///
  /// This enables English-to-Japanese lookup by searching within the
  /// JSON-encoded definition strings. Results are ordered by dictionary
  /// sort order and limited to [limit] entries.
  Future<List<DictionaryEntryWithSource>> glossarySearchWithSource(
    String term, {
    int limit = 30,
  }) async {
    if (term.isEmpty) return [];

    final cache = await _ensureMetasCached();
    if (cache.enabledIds.isEmpty) return [];

    final pattern = '%$term%';
    final query = _db.select(_db.dictionaryEntries)
      ..where(
        (t) =>
            t.glossaries.like(pattern) & t.dictionaryId.isIn(cache.enabledIds),
      )
      ..limit(limit);

    final rows = await query.get();
    final results = rows.map((entry) {
      return DictionaryEntryWithSource(
        entry: entry,
        dictionaryName: cache.names[entry.dictionaryId] ?? '',
      );
    }).toList();

    _sortWithSourceBySortOrder(results, cache);
    return results;
  }

  /// Search pitch accents by expression.
  /// Only returns results from enabled dictionaries, ordered by dictionary sort order.
  Future<List<PitchAccentResult>> searchPitchAccents(String expression) async {
    final cache = await _ensureMetasCached();
    if (cache.enabledIds.isEmpty) return [];

    final query = _db.select(_db.pitchAccents)
      ..where(
        (t) =>
            t.expression.equals(expression) &
            t.dictionaryId.isIn(cache.enabledIds),
      );

    final rows = await query.get();

    // Sort by dictionary sort order using the dictionaryId from each row.
    rows.sort((a, b) {
      final orderA = cache.sortOrders[a.dictionaryId] ?? 0;
      final orderB = cache.sortOrders[b.dictionaryId] ?? 0;
      return orderA.compareTo(orderB);
    });

    return rows.map((pitch) {
      return PitchAccentResult(
        reading: pitch.reading,
        downstepPosition: pitch.downstepPosition,
        dictionaryName: cache.names[pitch.dictionaryId] ?? '',
      );
    }).toList();
  }

  /// Fetch a broad set of candidates whose expression or reading starts with
  /// any of [searchTerms]. Used as the input dataset for fuzzy_bolt ranking.
  /// Merges all terms into a single query for efficiency.
  Future<List<DictionaryEntryWithSource>> _fetchPrefixCandidates(
    List<String> searchTerms, {
    int limit = 100,
  }) async {
    final nonEmptyTerms = searchTerms.where((t) => t.isNotEmpty).toList();
    if (nonEmptyTerms.isEmpty || limit <= 0) return [];

    final cache = await _ensureMetasCached();
    if (cache.enabledIds.isEmpty) return [];

    final patterns = nonEmptyTerms.map((t) => '$t%').toList(growable: false);

    final query = _db.select(_db.dictionaryEntries)
      ..where((t) {
        Expression<bool>? condition;
        for (final pattern in patterns) {
          final termCondition =
              t.expression.like(pattern) | t.reading.like(pattern);
          condition = condition == null
              ? termCondition
              : (condition | termCondition);
        }
        return condition! & t.dictionaryId.isIn(cache.enabledIds);
      })
      ..limit(limit);

    final rows = await query.get();
    return _mapEntriesWithSourceUnsorted(rows, cache);
  }

  static bool _isKanji(String char) {
    if (char.isEmpty) return false;
    final code = char.codeUnitAt(0);
    // CJK Unified Ideographs: U+4E00–U+9FFF
    // CJK Unified Ideographs Extension A: U+3400–U+4DBF
    return (code >= 0x4E00 && code <= 0x9FFF) ||
        (code >= 0x3400 && code <= 0x4DBF);
  }

  /// Returns `true` if [text] contains at least one Latin letter (a-z/A-Z).
  /// Used to decide whether to search glossary definitions (English input).
  static bool _hasLatinLetters(String text) {
    return _latinPattern.hasMatch(text);
  }

  static final _latinPattern = RegExp(r'[a-zA-Z]');
}
