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

  /// Next free position in [collectionId] — max + 1, or 0 when empty.
  Future<int> _nextPosition(int collectionId) async {
    final max = _db.bookCollections.position.max();
    final row =
        await (_db.selectOnly(_db.bookCollections)
              ..addColumns([max])
              ..where(_db.bookCollections.collectionId.equals(collectionId)))
            .getSingle();
    final current = row.read(max);
    return current == null ? 0 : current + 1;
  }

  /// Replaces [bookId]'s memberships with [collectionIds], diff-style.
  /// Rewriting every row would reset the manual [BookCollections.position]
  /// in each folder the book stays in, on every checkbox toggle.
  Future<void> setBookCollections(int bookId, Set<int> collectionIds) {
    return _db.transaction(() async {
      final current = await (_db.select(
        _db.bookCollections,
      )..where((t) => t.bookId.equals(bookId))).get();
      final currentIds = {for (final m in current) m.collectionId};
      final removed = currentIds.difference(collectionIds);
      if (removed.isNotEmpty) {
        await (_db.delete(_db.bookCollections)..where(
              (t) => t.bookId.equals(bookId) & t.collectionId.isIn(removed),
            ))
            .go();
      }
      for (final id in collectionIds.difference(currentIds)) {
        await _db
            .into(_db.bookCollections)
            .insert(
              BookCollectionsCompanion.insert(
                bookId: bookId,
                collectionId: id,
                position: Value(await _nextPosition(id)),
              ),
            );
      }
    });
  }

  /// Appends [bookIds] to [collectionId]. Books already filed there keep
  /// their place.
  Future<void> addBooksToCollection(int collectionId, Set<int> bookIds) {
    return _db.transaction(() async {
      final existing = await (_db.select(
        _db.bookCollections,
      )..where((t) => t.collectionId.equals(collectionId))).get();
      final existingIds = {for (final m in existing) m.bookId};
      var position = await _nextPosition(collectionId);
      for (final bookId in bookIds) {
        if (existingIds.contains(bookId)) continue;
        await _db
            .into(_db.bookCollections)
            .insert(
              BookCollectionsCompanion.insert(
                bookId: bookId,
                collectionId: collectionId,
                position: Value(position++),
              ),
              mode: InsertMode.insertOrIgnore,
            );
      }
    });
  }

  /// Removes [bookIds] from [collectionId]. Remaining positions keep their
  /// gaps — only relative order is ever read.
  Future<void> removeBooksFromCollection(int collectionId, Set<int> bookIds) {
    return (_db.delete(_db.bookCollections)..where(
          (t) => t.collectionId.equals(collectionId) & t.bookId.isIn(bookIds),
        ))
        .go();
  }

  /// Rewrites [collectionId]'s order as dense 0..n-1, mirroring
  /// DictionaryRepository.reorderDictionaries.
  Future<void> reorderCollectionBooks(
    int collectionId,
    List<int> orderedBookIds,
  ) {
    return _db.transaction(() async {
      for (var i = 0; i < orderedBookIds.length; i++) {
        await (_db.update(_db.bookCollections)..where(
              (t) =>
                  t.collectionId.equals(collectionId) &
                  t.bookId.equals(orderedBookIds[i]),
            ))
            .write(BookCollectionsCompanion(position: Value(i)));
      }
    });
  }
}
