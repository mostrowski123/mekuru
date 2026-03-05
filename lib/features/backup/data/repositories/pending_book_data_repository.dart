import 'package:drift/drift.dart';
import 'package:mekuru/core/database/database_provider.dart';

/// CRUD operations for the [PendingBookDatas] table.
class PendingBookDataRepository {
  final AppDatabase _db;

  PendingBookDataRepository(this._db);

  /// Insert or replace a pending book data entry for [bookKey].
  ///
  /// Keeps one row per key to avoid duplicate pending entries causing
  /// ambiguity when applying restore data after import.
  Future<int> insert(String bookKey, String dataJson) async {
    return _db.transaction(() async {
      await (_db.delete(
        _db.pendingBookDatas,
      )..where((t) => t.bookKey.equals(bookKey))).go();

      return _db
          .into(_db.pendingBookDatas)
          .insert(
            PendingBookDatasCompanion.insert(
              bookKey: bookKey,
              dataJson: dataJson,
            ),
          );
    });
  }

  /// Find a pending entry by book key. Returns `null` if not found.
  Future<PendingBookData?> findByBookKey(String bookKey) async {
    final query = _db.select(_db.pendingBookDatas)
      ..where((t) => t.bookKey.equals(bookKey))
      ..orderBy([
        (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
      ])
      ..limit(1);

    final rows = await query.get();
    if (rows.isEmpty) return null;
    return rows.first;
  }

  /// Get all pending book data entries.
  Future<List<PendingBookData>> getAll() {
    return _db.select(_db.pendingBookDatas).get();
  }

  /// Delete a pending entry by id.
  Future<int> deleteById(int id) {
    return (_db.delete(
      _db.pendingBookDatas,
    )..where((t) => t.id.equals(id))).go();
  }

  /// Delete all pending entries.
  Future<int> deleteAll() {
    return _db.delete(_db.pendingBookDatas).go();
  }
}
