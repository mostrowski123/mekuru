import 'package:drift/drift.dart';
import 'package:mekuru/core/database/database_provider.dart';

/// Repository for dictionary CRUD operations.
class DictionaryRepository {
  final AppDatabase _db;

  DictionaryRepository(this._db);

  // ──────────────── DictionaryMeta ────────────────

  /// Get all imported dictionaries, ordered by sort order.
  Future<List<DictionaryMeta>> getAllDictionaries() => (_db.select(
    _db.dictionaryMetas,
  )..orderBy([(t) => OrderingTerm.asc(t.sortOrder)])).get();

  /// Watch all imported dictionaries (reactive stream), ordered by sort order.
  Stream<List<DictionaryMeta>> watchAllDictionaries() => (_db.select(
    _db.dictionaryMetas,
  )..orderBy([(t) => OrderingTerm.asc(t.sortOrder)])).watch();

  /// Watch user-visible dictionaries (excludes hidden system dictionaries).
  Stream<List<DictionaryMeta>> watchVisibleDictionaries() =>
      (_db.select(_db.dictionaryMetas)
            ..where((t) => t.isHidden.equals(false))
            ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
          .watch();

  /// Insert a new dictionary and return its auto-generated id.
  /// Automatically assigns the next sort order (appends to end).
  Future<int> insertDictionary(String name) async {
    final nextOrder = await getNextSortOrder();
    return _db
        .into(_db.dictionaryMetas)
        .insert(
          DictionaryMetasCompanion.insert(
            name: name,
            sortOrder: Value(nextOrder),
          ),
        );
  }

  /// Get the next available sort order value (max + 1).
  Future<int> getNextSortOrder() async {
    final maxOrder = _db.dictionaryMetas.sortOrder.max();
    final query = _db.selectOnly(_db.dictionaryMetas)..addColumns([maxOrder]);
    final result = await query.getSingle();
    final currentMax = result.read(maxOrder);
    return (currentMax ?? -1) + 1;
  }

  /// Persist a new display order for dictionaries.
  /// [orderedIds] is the list of dictionary IDs in the desired order.
  Future<void> reorderDictionaries(List<int> orderedIds) async {
    await _db.transaction(() async {
      for (var i = 0; i < orderedIds.length; i++) {
        await (_db.update(_db.dictionaryMetas)
              ..where((t) => t.id.equals(orderedIds[i])))
            .write(DictionaryMetasCompanion(sortOrder: Value(i)));
      }
    });
  }

  /// Toggle dictionary enabled/disabled.
  Future<void> toggleDictionary(int id, {required bool isEnabled}) =>
      (_db.update(_db.dictionaryMetas)..where((t) => t.id.equals(id))).write(
        DictionaryMetasCompanion(isEnabled: Value(isEnabled)),
      );

  /// Mark a dictionary as hidden from the user-facing dictionary manager.
  Future<void> setHidden(int id, {required bool isHidden}) =>
      (_db.update(_db.dictionaryMetas)..where((t) => t.id.equals(id))).write(
        DictionaryMetasCompanion(isHidden: Value(isHidden)),
      );

  /// Delete a dictionary and all its entries (including pitch accents and frequencies).
  Future<void> deleteDictionary(int dictionaryId) async {
    await _db.transaction(() async {
      await (_db.delete(
        _db.dictionaryEntries,
      )..where((t) => t.dictionaryId.equals(dictionaryId))).go();
      await (_db.delete(
        _db.pitchAccents,
      )..where((t) => t.dictionaryId.equals(dictionaryId))).go();
      await (_db.delete(
        _db.frequencies,
      )..where((t) => t.dictionaryId.equals(dictionaryId))).go();
      await (_db.delete(
        _db.dictionaryMetas,
      )..where((t) => t.id.equals(dictionaryId))).go();
    });
  }

  /// Find a dictionary by its exact name, or null if not found.
  Future<DictionaryMeta?> getDictionaryByName(String name) => (_db.select(
    _db.dictionaryMetas,
  )..where((t) => t.name.equals(name))).getSingleOrNull();

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

  // ──────────────── PitchAccent ────────────────

  /// Batch insert pitch accent entries in chunks for performance.
  Future<int> batchInsertPitchAccents(
    List<PitchAccentsCompanion> entries, {
    int batchSize = 10000,
  }) async {
    int totalInserted = 0;
    for (var i = 0; i < entries.length; i += batchSize) {
      final end = (i + batchSize < entries.length)
          ? i + batchSize
          : entries.length;
      final batch = entries.sublist(i, end);

      await _db.batch((b) {
        b.insertAll(_db.pitchAccents, batch);
      });
      totalInserted += batch.length;
    }
    return totalInserted;
  }

  /// Get pitch accent count for a specific dictionary.
  Future<int> getPitchAccentCount(int dictionaryId) async {
    final count = _db.pitchAccents.id.count();
    final query = _db.selectOnly(_db.pitchAccents)
      ..addColumns([count])
      ..where(_db.pitchAccents.dictionaryId.equals(dictionaryId));
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }

  // ──────────────── Frequency ────────────────

  /// Batch insert frequency entries in chunks for performance.
  Future<int> batchInsertFrequencies(
    List<FrequenciesCompanion> entries, {
    int batchSize = 10000,
  }) async {
    int totalInserted = 0;
    for (var i = 0; i < entries.length; i += batchSize) {
      final end = (i + batchSize < entries.length)
          ? i + batchSize
          : entries.length;
      final batch = entries.sublist(i, end);

      await _db.batch((b) {
        b.insertAll(_db.frequencies, batch);
      });
      totalInserted += batch.length;
    }
    return totalInserted;
  }

  /// Get frequency entry count for a specific dictionary.
  Future<int> getFrequencyCount(int dictionaryId) async {
    final count = _db.frequencies.id.count();
    final query = _db.selectOnly(_db.frequencies)
      ..addColumns([count])
      ..where(_db.frequencies.dictionaryId.equals(dictionaryId));
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }
}
