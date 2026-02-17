import 'package:drift/drift.dart';
import 'package:fuzzy_bolt/fuzzy_bolt.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/services/romaji_converter.dart';

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

/// Service for querying dictionary entries.
class DictionaryQueryService {
  final AppDatabase _db;

  DictionaryQueryService(this._db);

  /// Search entries by exact expression match.
  /// Only returns results from enabled dictionaries, ordered by dictionary sort order.
  Future<List<DictionaryEntry>> searchByExpression(String expression) async {
    final query =
        _db.select(_db.dictionaryEntries).join([
            innerJoin(
              _db.dictionaryMetas,
              _db.dictionaryMetas.id.equalsExp(
                _db.dictionaryEntries.dictionaryId,
              ),
            ),
          ])
          ..where(_db.dictionaryEntries.expression.equals(expression))
          ..where(_db.dictionaryMetas.isEnabled.equals(true))
          ..orderBy([OrderingTerm.asc(_db.dictionaryMetas.sortOrder)]);

    final rows = await query.get();
    return rows.map((row) => row.readTable(_db.dictionaryEntries)).toList();
  }

  /// Search entries by reading (hiragana/katakana).
  /// Only returns results from enabled dictionaries, ordered by dictionary sort order.
  Future<List<DictionaryEntry>> searchByReading(String reading) async {
    final query =
        _db.select(_db.dictionaryEntries).join([
            innerJoin(
              _db.dictionaryMetas,
              _db.dictionaryMetas.id.equalsExp(
                _db.dictionaryEntries.dictionaryId,
              ),
            ),
          ])
          ..where(_db.dictionaryEntries.reading.equals(reading))
          ..where(_db.dictionaryMetas.isEnabled.equals(true))
          ..orderBy([OrderingTerm.asc(_db.dictionaryMetas.sortOrder)]);

    final rows = await query.get();
    return rows.map((row) => row.readTable(_db.dictionaryEntries)).toList();
  }

  /// Search entries by expression OR reading.
  /// Used for the lookup bottom sheet when we don't know
  /// if the selection is kanji or kana.
  /// Results are ordered by dictionary sort order (same order as Dictionary Manager).
  Future<List<DictionaryEntry>> search(String term) async {
    final query =
        _db.select(_db.dictionaryEntries).join([
            innerJoin(
              _db.dictionaryMetas,
              _db.dictionaryMetas.id.equalsExp(
                _db.dictionaryEntries.dictionaryId,
              ),
            ),
          ])
          ..where(
            _db.dictionaryEntries.expression.equals(term) |
                _db.dictionaryEntries.reading.equals(term),
          )
          ..where(_db.dictionaryMetas.isEnabled.equals(true))
          ..orderBy([OrderingTerm.asc(_db.dictionaryMetas.sortOrder)]);

    final rows = await query.get();
    return rows.map((row) => row.readTable(_db.dictionaryEntries)).toList();
  }

  /// Returns `true` if [term] exists as an expression or reading in any
  /// enabled dictionary. Uses LIMIT 1 for efficiency — only checks existence,
  /// does not fetch full entry data.
  Future<bool> hasMatch(String term) async {
    final query =
        _db.select(_db.dictionaryEntries).join([
            innerJoin(
              _db.dictionaryMetas,
              _db.dictionaryMetas.id.equalsExp(
                _db.dictionaryEntries.dictionaryId,
              ),
            ),
          ])
          ..where(
            _db.dictionaryEntries.expression.equals(term) |
                _db.dictionaryEntries.reading.equals(term),
          )
          ..where(_db.dictionaryMetas.isEnabled.equals(true))
          ..limit(1);

    final rows = await query.get();
    return rows.isNotEmpty;
  }

  /// Search entries and include the dictionary name for each result.
  /// Results are ordered by frequency rank (most common first), then by
  /// dictionary sort order as a tiebreaker.
  Future<List<DictionaryEntryWithSource>> searchWithSource(String term) async {
    final query =
        _db.select(_db.dictionaryEntries).join([
            innerJoin(
              _db.dictionaryMetas,
              _db.dictionaryMetas.id.equalsExp(
                _db.dictionaryEntries.dictionaryId,
              ),
            ),
          ])
          ..where(
            _db.dictionaryEntries.expression.equals(term) |
                _db.dictionaryEntries.reading.equals(term),
          )
          ..where(_db.dictionaryMetas.isEnabled.equals(true))
          ..orderBy([OrderingTerm.asc(_db.dictionaryMetas.sortOrder)]);

    final rows = await query.get();
    final results = rows.map((row) {
      final entry = row.readTable(_db.dictionaryEntries);
      final meta = row.readTable(_db.dictionaryMetas);
      return DictionaryEntryWithSource(
        entry: entry,
        dictionaryName: meta.name,
      );
    }).toList();

    return _attachFrequencyRanks(results);
  }

  /// Look up the best (lowest) frequency rank for a given expression.
  /// Queries all frequency dictionaries regardless of isEnabled flag.
  Future<int?> getFrequencyRank(String expression, [String reading = '']) async {
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

  /// Batch-query frequency ranks for a list of entries.
  /// Returns a map from expression to the best (lowest) frequency rank.
  Future<Map<String, int>> _getFrequencyRanksForExpressions(
    Set<String> expressions,
  ) async {
    if (expressions.isEmpty) return {};

    final ranks = <String, int>{};
    // Query in batches to avoid overly large IN clauses
    final exprList = expressions.toList();
    const batchSize = 200;

    for (var i = 0; i < exprList.length; i += batchSize) {
      final end = (i + batchSize < exprList.length) ? i + batchSize : exprList.length;
      final batch = exprList.sublist(i, end);

      final query = _db.select(_db.frequencies)
        ..where((t) => t.expression.isIn(batch));

      final rows = await query.get();
      for (final row in rows) {
        final existing = ranks[row.expression];
        if (existing == null || row.frequencyRank < existing) {
          ranks[row.expression] = row.frequencyRank;
        }
      }
    }

    return ranks;
  }

  /// Attach frequency ranks to a list of results and sort by rank (lowest first).
  /// Entries without frequency data are placed at the end.
  Future<List<DictionaryEntryWithSource>> _attachFrequencyRanks(
    List<DictionaryEntryWithSource> results,
  ) async {
    if (results.isEmpty) return results;

    final expressions = results.map((r) => r.entry.expression).toSet();
    final ranks = await _getFrequencyRanksForExpressions(expressions);

    final ranked = results.map((r) {
      final rank = ranks[r.entry.expression];
      return r.withFrequencyRank(rank);
    }).toList();

    // Stable sort: entries with frequency come first (lower rank = more common)
    ranked.sort((a, b) {
      if (a.frequencyRank == null && b.frequencyRank == null) return 0;
      if (a.frequencyRank == null) return 1;
      if (b.frequencyRank == null) return -1;
      return a.frequencyRank!.compareTo(b.frequencyRank!);
    });

    return ranked;
  }

  /// Prefix search: expression or reading starts with [term].
  /// Returns up to [limit] results from enabled dictionaries.
  Future<List<DictionaryEntryWithSource>> prefixSearchWithSource(
    String term, {
    int limit = 50,
  }) async {
    if (term.isEmpty) return [];

    final pattern = '$term%';
    final query =
        _db.select(_db.dictionaryEntries).join([
            innerJoin(
              _db.dictionaryMetas,
              _db.dictionaryMetas.id.equalsExp(
                _db.dictionaryEntries.dictionaryId,
              ),
            ),
          ])
          ..where(
            _db.dictionaryEntries.expression.like(pattern) |
                _db.dictionaryEntries.reading.like(pattern),
          )
          ..where(_db.dictionaryMetas.isEnabled.equals(true))
          ..orderBy([OrderingTerm.asc(_db.dictionaryMetas.sortOrder)])
          ..limit(limit);

    final rows = await query.get();
    return rows.map((row) {
      final entry = row.readTable(_db.dictionaryEntries);
      final meta = row.readTable(_db.dictionaryMetas);
      return DictionaryEntryWithSource(
        entry: entry,
        dictionaryName: meta.name,
      );
    }).toList();
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
      addTo(exactResults, await searchWithSource(t));
    }

    // 2. Fuzzy matches on expression/reading via fuzzy_bolt
    final prefixCandidates =
        await _fetchPrefixCandidates(searchTerms, limit: 100);
    if (prefixCandidates.isNotEmpty) {
      for (final t in searchTerms) {
        final fuzzyMatches =
            await FuzzyBolt.search<DictionaryEntryWithSource>(
              prefixCandidates,
              t,
              selectors: [
                (e) => e.entry.expression,
                (e) => e.entry.reading,
              ],
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
          addTo(subComponentResults, await searchWithSource(char));
        }
      }
    }

    // 4. English definition fuzzy search via fuzzy_bolt
    if (_hasLatinLetters(term)) {
      final glossaryCandidates =
          await _fetchGlossaryCandidates(term, limit: 100);
      if (glossaryCandidates.isNotEmpty) {
        final fuzzyMatches =
            await FuzzyBolt.search<DictionaryEntryWithSource>(
              glossaryCandidates,
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

    // Attach frequency ranks per tier, then concatenate in tier order.
    // This ensures exact matches always appear before fuzzy, which appear
    // before sub-component kanji matches, etc. — regardless of frequency.
    final rankedExact = await _attachFrequencyRanks(exactResults);
    final rankedFuzzy = await _attachFrequencyRanks(fuzzyResults);
    final rankedSubComponent = await _attachFrequencyRanks(subComponentResults);
    final rankedGlossary = await _attachFrequencyRanks(glossaryResults);

    return [
      ...rankedExact,
      ...rankedFuzzy,
      ...rankedSubComponent,
      ...rankedGlossary,
    ];
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

    final pattern = '%$term%';
    final query =
        _db.select(_db.dictionaryEntries).join([
            innerJoin(
              _db.dictionaryMetas,
              _db.dictionaryMetas.id.equalsExp(
                _db.dictionaryEntries.dictionaryId,
              ),
            ),
          ])
          ..where(_db.dictionaryEntries.glossaries.like(pattern))
          ..where(_db.dictionaryMetas.isEnabled.equals(true))
          ..orderBy([OrderingTerm.asc(_db.dictionaryMetas.sortOrder)])
          ..limit(limit);

    final rows = await query.get();
    return rows.map((row) {
      final entry = row.readTable(_db.dictionaryEntries);
      final meta = row.readTable(_db.dictionaryMetas);
      return DictionaryEntryWithSource(
        entry: entry,
        dictionaryName: meta.name,
      );
    }).toList();
  }

  /// Search pitch accents by expression.
  /// Only returns results from enabled dictionaries, ordered by dictionary sort order.
  Future<List<PitchAccentResult>> searchPitchAccents(String expression) async {
    final query =
        _db.select(_db.pitchAccents).join([
            innerJoin(
              _db.dictionaryMetas,
              _db.dictionaryMetas.id.equalsExp(
                _db.pitchAccents.dictionaryId,
              ),
            ),
          ])
          ..where(_db.pitchAccents.expression.equals(expression))
          ..where(_db.dictionaryMetas.isEnabled.equals(true))
          ..orderBy([OrderingTerm.asc(_db.dictionaryMetas.sortOrder)]);

    final rows = await query.get();
    return rows.map((row) {
      final pitch = row.readTable(_db.pitchAccents);
      final meta = row.readTable(_db.dictionaryMetas);
      return PitchAccentResult(
        reading: pitch.reading,
        downstepPosition: pitch.downstepPosition,
        dictionaryName: meta.name,
      );
    }).toList();
  }

  /// Fetch a broad set of candidates whose expression or reading starts with
  /// any of [searchTerms]. Used as the input dataset for fuzzy_bolt ranking.
  Future<List<DictionaryEntryWithSource>> _fetchPrefixCandidates(
    List<String> searchTerms, {
    int limit = 100,
  }) async {
    final allResults = <DictionaryEntryWithSource>[];
    final seenIds = <int>{};

    for (final term in searchTerms) {
      if (term.isEmpty) continue;

      final pattern = '$term%';
      final query = _db.select(_db.dictionaryEntries).join([
        innerJoin(
          _db.dictionaryMetas,
          _db.dictionaryMetas.id.equalsExp(
            _db.dictionaryEntries.dictionaryId,
          ),
        ),
      ])
        ..where(
          _db.dictionaryEntries.expression.like(pattern) |
              _db.dictionaryEntries.reading.like(pattern),
        )
        ..where(_db.dictionaryMetas.isEnabled.equals(true))
        ..limit(limit);

      final rows = await query.get();
      for (final row in rows) {
        final entry = row.readTable(_db.dictionaryEntries);
        if (seenIds.add(entry.id)) {
          final meta = row.readTable(_db.dictionaryMetas);
          allResults.add(
            DictionaryEntryWithSource(
              entry: entry,
              dictionaryName: meta.name,
            ),
          );
        }
      }
    }

    return allResults;
  }

  /// Fetch candidate entries whose glossary text contains [term].
  /// Used as the input dataset for fuzzy_bolt ranking of English definitions.
  Future<List<DictionaryEntryWithSource>> _fetchGlossaryCandidates(
    String term, {
    int limit = 100,
  }) async {
    if (term.isEmpty) return [];

    final pattern = '%$term%';
    final query = _db.select(_db.dictionaryEntries).join([
      innerJoin(
        _db.dictionaryMetas,
        _db.dictionaryMetas.id.equalsExp(
          _db.dictionaryEntries.dictionaryId,
        ),
      ),
    ])
      ..where(_db.dictionaryEntries.glossaries.like(pattern))
      ..where(_db.dictionaryMetas.isEnabled.equals(true))
      ..limit(limit);

    final rows = await query.get();
    return rows.map((row) {
      final entry = row.readTable(_db.dictionaryEntries);
      final meta = row.readTable(_db.dictionaryMetas);
      return DictionaryEntryWithSource(
        entry: entry,
        dictionaryName: meta.name,
      );
    }).toList();
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
