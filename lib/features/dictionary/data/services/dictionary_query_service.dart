import 'package:drift/drift.dart';
import 'package:fuzzy_bolt/fuzzy_bolt.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/services/romaji_converter.dart';
import 'package:mekuru/features/reader/data/services/deinflection.dart';

/// A dictionary entry paired with the name of the dictionary it came from.
class DictionaryEntryWithSource {
  final DictionaryEntry entry;
  final String dictionaryName;
  final int? frequencyRank;

  const DictionaryEntryWithSource({
    required this.entry,
    required this.dictionaryName,
    this.frequencyRank,
  });

  /// Returns a qualitative label for the frequency rank.
  static String? frequencyLabel(int? rank) {
    if (rank == null) return null;
    if (rank <= 5000) return 'Very Common';
    if (rank <= 15000) return 'Common';
    if (rank <= 30000) return 'Uncommon';
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
  /// Results are ordered by dictionary sort order (same order as Dictionary Manager).
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
    _sortBySortOrder(results, cache);
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
  /// Results are ordered by frequency rank (most common first), then by
  /// dictionary sort order as a tiebreaker.
  Future<List<DictionaryEntryWithSource>> searchWithSource(String term) async {
    final cache = await _ensureMetasCached();
    if (cache.enabledIds.isEmpty) return [];

    final results = await _searchWithSourceNoFrequency(term, cache);
    return _attachFrequencyRanks(results);
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
  /// 2. Fall back to the best (lowest) rank for that expression across all
  ///    readings when no reading-specific frequency exists.
  Future<Map<(String, String), int>> _getFrequencyRanks(
    List<DictionaryEntryWithSource> results,
  ) async {
    if (results.isEmpty) return {};

    final expressions = results.map((r) => r.entry.expression).toSet();
    if (expressions.isEmpty) return {};

    // Fetch ALL frequency rows for these expressions in batches.
    final allRows = <TypedResult>[];
    final exprList = expressions.toList();
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

    // Build three lookup structures:
    // 1. (expression, reading) → min rank  (reading-specific)
    // 2. expression → min rank from empty-reading rows (expression-level only)
    // 3. Set of expressions that have at least one reading-specific entry
    final pairRanks = <(String, String), int>{};
    final exprOnlyFallback = <String, int>{};
    final hasReadingSpecificData = <String>{};

    for (final row in allRows) {
      final expression = row.read(_db.frequencies.expression);
      final reading = row.read(_db.frequencies.reading);
      final frequencyRank = row.read(_db.frequencies.frequencyRank);
      if (expression == null || reading == null || frequencyRank == null) {
        continue;
      }

      if (reading.isNotEmpty) {
        hasReadingSpecificData.add(expression);
        final key = (expression, reading);
        final existing = pairRanks[key];
        if (existing == null || frequencyRank < existing) {
          pairRanks[key] = frequencyRank;
        }
      } else {
        // Expression-level frequency (no reading) — safe as fallback
        final existing = exprOnlyFallback[expression];
        if (existing == null || frequencyRank < existing) {
          exprOnlyFallback[expression] = frequencyRank;
        }
      }
    }

    // For each unique (expression, reading) in results, prefer the
    // pair-specific rank. Only fall back to expression-level rank when
    // the frequency dict has NO reading-specific data for this expression
    // (i.e. it only stores expression-level frequencies). When reading-
    // specific data exists but this particular reading isn't listed,
    // leave the rank as null so it sorts to the end.
    final resultPairs = results
        .map((r) => (r.entry.expression, r.entry.reading))
        .toSet();

    final ranks = <(String, String), int>{};
    for (final pair in resultPairs) {
      final pairRank = pairRanks[pair];
      if (pairRank != null) {
        ranks[pair] = pairRank;
      } else if (!hasReadingSpecificData.contains(pair.$1)) {
        final fallback = exprOnlyFallback[pair.$1];
        if (fallback != null) {
          ranks[pair] = fallback;
        }
      }
    }

    return ranks;
  }

  /// Attach frequency ranks and group results by (expression, reading).
  ///
  /// Within each group, entries retain their original order (which is the
  /// dictionary sort_order from the SQL query). Groups are ordered by their
  /// frequency rank (lowest rank first, null-rank groups last).
  Future<List<DictionaryEntryWithSource>> _attachFrequencyRanks(
    List<DictionaryEntryWithSource> results,
  ) async {
    if (results.isEmpty) return results;

    final ranks = await _getFrequencyRanks(results);
    return _applyFrequencyRanks(results, ranks);
  }

  /// Apply pre-fetched frequency ranks and group/sort results.
  List<DictionaryEntryWithSource> _applyFrequencyRanks(
    List<DictionaryEntryWithSource> results,
    Map<(String, String), int> ranks,
  ) {
    if (results.isEmpty) return results;

    // Attach frequency ranks to each entry.
    final ranked = results.map((r) {
      final rank = ranks[(r.entry.expression, r.entry.reading)];
      return r.withFrequencyRank(rank);
    }).toList();

    // Group by (expression, reading), preserving insertion order within
    // each group (which is the SQL sort_order).
    final groups = <(String, String), List<DictionaryEntryWithSource>>{};
    for (final r in ranked) {
      final key = (r.entry.expression, r.entry.reading);
      groups.putIfAbsent(key, () => []).add(r);
    }

    // Sort group keys by frequency rank (lowest first, null last).
    final sortedKeys = groups.keys.toList()
      ..sort((a, b) {
        final rankA = ranks[a];
        final rankB = ranks[b];
        if (rankA == null && rankB == null) return 0;
        if (rankA == null) return 1;
        if (rankB == null) return -1;
        return rankA.compareTo(rankB);
      });

    // Flatten groups back into a single list.
    return [for (final key in sortedKeys) ...groups[key]!];
  }

  /// Search entries matching any of [terms] (by expression or reading).
  /// Returns results from enabled dictionaries, ordered by frequency rank.
  /// Useful for searching multiple deinflected candidate forms at once.
  Future<List<DictionaryEntryWithSource>> searchMultipleWithSource(
    List<String> terms,
  ) async {
    if (terms.isEmpty) return [];

    final cache = await _ensureMetasCached();
    if (cache.enabledIds.isEmpty) return [];

    final results = await _searchMultipleWithSourceNoFrequency(terms, cache);
    return _attachFrequencyRanks(results);
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
    final ranks = await _getFrequencyRanks(allResults);

    return [
      ..._applyFrequencyRanks(exactResults, ranks),
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
