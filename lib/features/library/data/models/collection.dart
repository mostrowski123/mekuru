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

  @override
  Set<Column> get primaryKey => {bookId, collectionId};
}
