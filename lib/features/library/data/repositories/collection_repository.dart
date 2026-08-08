import 'package:drift/drift.dart';

import '../../../../core/database/database_provider.dart';

/// CRUD for user-created collections and book membership.
///
/// PRAGMA foreign_keys is off app-wide, so membership cleanup is enforced
/// here (and in [BookRepository.deleteBook]) rather than by the schema.
class CollectionRepository {
  final AppDatabase _db;

  CollectionRepository(this._db);

  Stream<List<Collection>> watchCollections() {
    return (_db.select(
      _db.collections,
    )..orderBy([(t) => OrderingTerm(expression: t.name)])).watch();
  }

  Stream<List<BookCollection>> watchMemberships() {
    return _db.select(_db.bookCollections).watch();
  }

  /// Returns the new collection's id.
  Future<int> createCollection(String name) {
    return _db
        .into(_db.collections)
        .insert(CollectionsCompanion.insert(name: name));
  }

  Future<void> renameCollection(int id, String name) async {
    await (_db.update(_db.collections)..where((t) => t.id.equals(id))).write(
      CollectionsCompanion(name: Value(name)),
    );
  }

  /// Deletes the collection and its memberships. Books are never deleted.
  Future<void> deleteCollection(int id) {
    return _db.transaction(() async {
      await (_db.delete(
        _db.bookCollections,
      )..where((t) => t.collectionId.equals(id))).go();
      await (_db.delete(_db.collections)..where((t) => t.id.equals(id))).go();
    });
  }

  /// Replaces [bookId]'s memberships with [collectionIds].
  Future<void> setBookCollections(int bookId, Set<int> collectionIds) {
    return _db.transaction(() async {
      await (_db.delete(
        _db.bookCollections,
      )..where((t) => t.bookId.equals(bookId))).go();
      await _db.batch(
        (batch) => batch.insertAll(_db.bookCollections, [
          for (final id in collectionIds)
            BookCollectionsCompanion.insert(bookId: bookId, collectionId: id),
        ]),
      );
    });
  }
}
