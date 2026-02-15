import 'package:drift/drift.dart';
import 'package:mekuru/core/database/database_provider.dart';

/// A dictionary entry paired with the name of the dictionary it came from.
class DictionaryEntryWithSource {
  final DictionaryEntry entry;
  final String dictionaryName;

  const DictionaryEntryWithSource({
    required this.entry,
    required this.dictionaryName,
  });
}

/// Service for querying dictionary entries.
class DictionaryQueryService {
  final AppDatabase _db;

  DictionaryQueryService(this._db);

  /// Search entries by exact expression match.
  /// Only returns results from enabled dictionaries, ordered by dictionary id.
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
          ..orderBy([OrderingTerm.asc(_db.dictionaryMetas.id)]);

    final rows = await query.get();
    return rows.map((row) => row.readTable(_db.dictionaryEntries)).toList();
  }

  /// Search entries by reading (hiragana/katakana).
  /// Only returns results from enabled dictionaries, ordered by dictionary id.
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
          ..orderBy([OrderingTerm.asc(_db.dictionaryMetas.id)]);

    final rows = await query.get();
    return rows.map((row) => row.readTable(_db.dictionaryEntries)).toList();
  }

  /// Search entries by expression OR reading.
  /// Used for the lookup bottom sheet when we don't know
  /// if the selection is kanji or kana.
  /// Results are ordered by dictionary id (same order as Dictionary Manager).
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
          ..orderBy([OrderingTerm.asc(_db.dictionaryMetas.id)]);

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
  /// Results are ordered by dictionary id (same order as Dictionary Manager).
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
          ..orderBy([OrderingTerm.asc(_db.dictionaryMetas.id)]);

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
}
