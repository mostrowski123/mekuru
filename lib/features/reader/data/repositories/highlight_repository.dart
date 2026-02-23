import 'package:drift/drift.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Repository for managing text highlights within a book.
class HighlightRepository {
  final AppDatabase _db;

  HighlightRepository(this._db);

  // ──────────────── Queries ────────────────

  /// Watch highlights for a specific book (reactive stream, newest first).
  Stream<List<Highlight>> watchHighlightsForBook(int bookId) =>
      (_db.select(_db.highlights)
            ..where((t) => t.bookId.equals(bookId))
            ..orderBy([(t) => OrderingTerm.desc(t.dateAdded)]))
          .watch();

  /// Get all highlights for a book (non-reactive, used for restoring on load).
  Future<List<Highlight>> getAllHighlightsForBook(int bookId) =>
      (_db.select(_db.highlights)
            ..where((t) => t.bookId.equals(bookId))
            ..orderBy([(t) => OrderingTerm.asc(t.dateAdded)]))
          .get();

  // ──────────────── CRUD ────────────────

  /// Add a highlight for selected text.
  Future<int> addHighlight({
    required int bookId,
    required String cfiRange,
    required String selectedText,
    String color = 'yellow',
    String userNote = '',
  }) async {
    final id = await _db.into(_db.highlights).insert(
          HighlightsCompanion.insert(
            bookId: bookId,
            cfiRange: cfiRange,
            selectedText: selectedText,
            color: Value(color),
            userNote: Value(userNote),
          ),
        );

    Sentry.addBreadcrumb(Breadcrumb(
      message: 'Highlight added',
      category: 'highlights',
    ));

    return id;
  }

  /// Update the user note on a highlight.
  Future<void> updateHighlightNote(int id, String note) =>
      (_db.update(_db.highlights)..where((t) => t.id.equals(id)))
          .write(HighlightsCompanion(userNote: Value(note)));

  /// Update the color of a highlight.
  Future<void> updateHighlightColor(int id, String color) =>
      (_db.update(_db.highlights)..where((t) => t.id.equals(id)))
          .write(HighlightsCompanion(color: Value(color)));

  /// Delete a highlight by ID.
  Future<void> deleteHighlight(int id) =>
      (_db.delete(_db.highlights)..where((t) => t.id.equals(id))).go();

  /// Delete all highlights for a book (used when deleting a book).
  Future<void> deleteHighlightsForBook(int bookId) =>
      (_db.delete(_db.highlights)..where((t) => t.bookId.equals(bookId))).go();
}
