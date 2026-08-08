import 'package:drift/drift.dart';

import 'book.dart';

/// User-created shelves for organizing the library. A book can belong to any
/// number of collections.
class Collections extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
}

/// Book ↔ collection membership. The references are documentation only:
/// PRAGMA foreign_keys is off app-wide (as with Bookmarks/Highlights), so
/// cascade deletes are enforced in repository code instead.
class BookCollections extends Table {
  IntColumn get bookId => integer().references(Books, #id)();
  IntColumn get collectionId => integer().references(Collections, #id)();

  /// Manual order within one collection. Rows written before v22 all sit
  /// at 0; the folder grid tie-breaks those by the library sort, so an
  /// un-reordered collection looks exactly as it did.
  IntColumn get position => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {bookId, collectionId};
}
