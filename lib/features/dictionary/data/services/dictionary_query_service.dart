import 'package:drift/drift.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/services/romaji_converter.dart';

/// A dictionary entry paired with the name of the dictionary it came from.
class DictionaryEntryWithSource {
  final DictionaryEntry entry;
  final String dictionaryName;

  const DictionaryEntryWithSource({
    required this.entry,
    required this.dictionaryName,
  });
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
  /// Results are ordered by dictionary sort order (same order as Dictionary Manager).
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
    return rows.map((row) {
      final entry = row.readTable(_db.dictionaryEntries);
      final meta = row.readTable(_db.dictionaryMetas);
      return DictionaryEntryWithSource(
        entry: entry,
        dictionaryName: meta.name,
      );
    }).toList();
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

  /// Fuzzy search combining exact match, prefix match, and sub-component matches.
  ///
  /// For romaji input, converts to hiragana and searches by reading.
  /// For katakana input, also searches the hiragana equivalent.
  /// For kanji input, also decomposes into individual kanji for sub-matches.
  ///
  /// Results are ordered by relevance: exact matches first, then prefix matches,
  /// then sub-component matches. Within each group, dictionary sort order applies.
  Future<List<DictionaryEntryWithSource>> fuzzySearchWithSource(
    String term,
  ) async {
    if (term.isEmpty) return [];

    final results = <DictionaryEntryWithSource>[];
    final seenIds = <int>{};

    void addResults(List<DictionaryEntryWithSource> newResults) {
      for (final r in newResults) {
        if (seenIds.add(r.entry.id)) {
          results.add(r);
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

    // 1. Exact matches
    for (final t in searchTerms) {
      addResults(await searchWithSource(t));
    }

    // 2. Prefix matches
    for (final t in searchTerms) {
      addResults(await prefixSearchWithSource(t, limit: 30));
    }

    // 3. Sub-component matches (individual kanji from original term)
    if (!isRomaji && term.length > 1) {
      final seen = <String>{};
      for (final rune in term.runes) {
        final char = String.fromCharCode(rune);
        if (_isKanji(char) && seen.add(char)) {
          addResults(await searchWithSource(char));
        }
      }
    }

    return results;
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

  static bool _isKanji(String char) {
    if (char.isEmpty) return false;
    final code = char.codeUnitAt(0);
    // CJK Unified Ideographs: U+4E00–U+9FFF
    // CJK Unified Ideographs Extension A: U+3400–U+4DBF
    return (code >= 0x4E00 && code <= 0x9FFF) ||
        (code >= 0x3400 && code <= 0x4DBF);
  }
}
