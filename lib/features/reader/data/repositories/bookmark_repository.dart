import 'package:drift/drift.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Repository for managing bookmarks within a book.
class BookmarkRepository {
  final AppDatabase _db;

  BookmarkRepository(this._db);

  // ──────────────── Queries ────────────────

  /// Watch bookmarks for a specific book (reactive stream, newest first).
  Stream<List<Bookmark>> watchBookmarksForBook(int bookId) =>
      (_db.select(_db.bookmarks)
            ..where((t) => t.bookId.equals(bookId))
            ..orderBy([(t) => OrderingTerm.desc(t.dateAdded)]))
          .watch();

  /// Get all bookmarks for a book (non-reactive).
  Future<List<Bookmark>> getBookmarksForBook(int bookId) =>
      (_db.select(_db.bookmarks)
            ..where((t) => t.bookId.equals(bookId))
            ..orderBy([(t) => OrderingTerm.desc(t.dateAdded)]))
          .get();

  /// Find a bookmark at a specific CFI for a book (for toggle detection).
  Future<Bookmark?> getBookmarkAtCfi(int bookId, String cfi) async {
    final results = await (_db.select(_db.bookmarks)
          ..where((t) => t.bookId.equals(bookId) & t.cfi.equals(cfi)))
        .get();
    return results.isEmpty ? null : results.first;
  }

  // ──────────────── CRUD ────────────────

  /// Add a bookmark at the current reading position.
  Future<int> addBookmark({
    required int bookId,
    required String cfi,
    double progress = 0.0,
    String chapterTitle = '',
    String userNote = '',
  }) async {
    final id = await _db.into(_db.bookmarks).insert(
          BookmarksCompanion.insert(
            bookId: bookId,
            cfi: cfi,
            progress: Value(progress),
            chapterTitle: Value(chapterTitle),
            userNote: Value(userNote),
          ),
        );

    Sentry.addBreadcrumb(Breadcrumb(
      message: 'Bookmark added',
      category: 'bookmarks',
    ));

    return id;
  }

  /// Delete a bookmark by ID.
  Future<void> deleteBookmark(int id) =>
      (_db.delete(_db.bookmarks)..where((t) => t.id.equals(id))).go();

  /// Delete all bookmarks for a book (used when deleting a book).
  Future<void> deleteBookmarksForBook(int bookId) =>
      (_db.delete(_db.bookmarks)..where((t) => t.bookId.equals(bookId))).go();
}
