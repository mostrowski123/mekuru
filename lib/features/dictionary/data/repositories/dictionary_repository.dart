import 'package:drift/drift.dart';
import 'package:mekuru/core/database/database_provider.dart';

/// Repository for dictionary CRUD operations.
class DictionaryRepository {
  final AppDatabase _db;

  DictionaryRepository(this._db);

  // ──────────────── DictionaryMeta ────────────────

  /// Get all imported dictionaries.
  Future<List<DictionaryMeta>> getAllDictionaries() =>
      _db.select(_db.dictionaryMetas).get();

  /// Watch all imported dictionaries (reactive stream).
  Stream<List<DictionaryMeta>> watchAllDictionaries() =>
      _db.select(_db.dictionaryMetas).watch();

  /// Insert a new dictionary and return its auto-generated id.
  Future<int> insertDictionary(String name) => _db
      .into(_db.dictionaryMetas)
      .insert(DictionaryMetasCompanion.insert(name: name));

  /// Toggle dictionary enabled/disabled.
  Future<void> toggleDictionary(int id, {required bool isEnabled}) =>
      (_db.update(_db.dictionaryMetas)..where((t) => t.id.equals(id))).write(
        DictionaryMetasCompanion(isEnabled: Value(isEnabled)),
      );

  /// Delete a dictionary and all its entries.
  Future<void> deleteDictionary(int dictionaryId) async {
    await _db.transaction(() async {
      await (_db.delete(
        _db.dictionaryEntries,
      )..where((t) => t.dictionaryId.equals(dictionaryId))).go();
      await (_db.delete(
        _db.dictionaryMetas,
      )..where((t) => t.id.equals(dictionaryId))).go();
    });
  }

  // ──────────────── DictionaryEntry ────────────────

  /// Batch insert entries in chunks for performance.
  /// Returns total number of entries inserted.
  Future<int> batchInsertEntries(
    List<DictionaryEntriesCompanion> entries, {
    int batchSize = 10000,
  }) async {
    int totalInserted = 0;
    for (var i = 0; i < entries.length; i += batchSize) {
      final end = (i + batchSize < entries.length)
          ? i + batchSize
          : entries.length;
      final batch = entries.sublist(i, end);

      await _db.batch((b) {
        b.insertAll(_db.dictionaryEntries, batch);
      });
      totalInserted += batch.length;
    }
    return totalInserted;
  }

  /// Get total entry count for a specific dictionary.
  Future<int> getEntryCount(int dictionaryId) async {
    final count = _db.dictionaryEntries.id.count();
    final query = _db.selectOnly(_db.dictionaryEntries)
      ..addColumns([count])
      ..where(_db.dictionaryEntries.dictionaryId.equals(dictionaryId));
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }

  /// Get total entry count across all dictionaries.
  Future<int> getTotalEntryCount() async {
    final count = _db.dictionaryEntries.id.count();
    final query = _db.selectOnly(_db.dictionaryEntries)..addColumns([count]);
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }
}
