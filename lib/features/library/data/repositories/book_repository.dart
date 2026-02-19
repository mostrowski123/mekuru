import 'dart:io';

import 'package:drift/drift.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/library/data/services/epub_parser.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Repository for book CRUD operations and EPUB import.
class BookRepository {
  final AppDatabase _db;

  BookRepository(this._db);

  // ──────────────── Queries ────────────────

  /// Get all books ordered by date added (newest first).
  Future<List<Book>> getAllBooks() => (_db.select(
    _db.books,
  )..orderBy([(t) => OrderingTerm.desc(t.dateAdded)])).get();

  /// Watch all books (reactive stream).
  Stream<List<Book>> watchAllBooks() => (_db.select(
    _db.books,
  )..orderBy([(t) => OrderingTerm.desc(t.dateAdded)])).watch();

  /// Get a single book by id.
  Future<Book?> getBookById(int id) =>
      (_db.select(_db.books)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Get the most recently read book (by [lastReadAt]).
  /// Returns `null` if no book has been opened yet.
  Future<Book?> getMostRecentlyReadBook() => (_db.select(_db.books)
        ..where((t) => t.lastReadAt.isNotNull())
        ..orderBy([(t) => OrderingTerm.desc(t.lastReadAt)])
        ..limit(1))
      .getSingleOrNull();

  // ──────────────── Import ────────────────

  /// Import an EPUB file into the library.
  ///
  /// 1. Copies the EPUB to app storage
  /// 2. Unzips and parses metadata
  /// 3. Extracts cover image
  /// 4. Creates a Book entry in the database
  ///
  /// Returns the created [Book].
  Future<Book> importEpub(String sourcePath) async {
    final appDir = await getApplicationSupportDirectory();
    final booksDir = Directory(p.join(appDir.path, 'books'));

    // Generate a unique directory name for this book
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final bookDir = Directory(p.join(booksDir.path, 'book_$timestamp'));
    await bookDir.create(recursive: true);

    // Copy EPUB to app storage
    final epubFileName = p.basename(sourcePath);
    final storedEpubPath = p.join(bookDir.path, epubFileName);
    await File(sourcePath).copy(storedEpubPath);

    // Unzip to a subdirectory
    final extractDir = p.join(bookDir.path, 'content');
    await Directory(extractDir).create(recursive: true);

    // Parse EPUB metadata
    final metadata = await EpubParser.parseEpub(storedEpubPath, extractDir);

    // Resolve cover image path
    String? coverImagePath;
    if (metadata.coverImageRelativePath != null) {
      final coverPath = p.join(extractDir, metadata.coverImageRelativePath!);
      if (await File(coverPath).exists()) {
        coverImagePath = coverPath;
      }
    }

    // Insert into database
    final bookId = await _db
        .into(_db.books)
        .insert(
          BooksCompanion.insert(
            title: metadata.title,
            filePath: extractDir,
            coverImagePath: coverImagePath != null
                ? Value(coverImagePath)
                : const Value.absent(),
            language: metadata.language != null
                ? Value(metadata.language)
                : const Value.absent(),
            pageProgressionDirection:
                metadata.pageProgressionDirection != null
                    ? Value(metadata.pageProgressionDirection)
                    : const Value.absent(),
            primaryWritingMode: metadata.primaryWritingMode != null
                ? Value(metadata.primaryWritingMode)
                : const Value.absent(),
          ),
        );

    return (await getBookById(bookId))!;
  }

  // ──────────────── Update ────────────────

  /// Update reading progress (CFI / scroll position and percentage).
  Future<void> updateProgress(int bookId, String cfi, {double? progress}) =>
      (_db.update(_db.books)..where((t) => t.id.equals(bookId))).write(
        BooksCompanion(
          lastReadCfi: Value(cfi),
          readProgress:
              progress != null ? Value(progress) : const Value.absent(),
          lastReadAt: Value(DateTime.now()),
        ),
      );

  /// Update total pages count.
  Future<void> updateTotalPages(int bookId, int totalPages) =>
      (_db.update(_db.books)..where((t) => t.id.equals(bookId))).write(
        BooksCompanion(totalPages: Value(totalPages)),
      );

  /// Update the book title (rename).
  Future<void> updateTitle(int bookId, String title) =>
      (_db.update(_db.books)..where((t) => t.id.equals(bookId))).write(
        BooksCompanion(title: Value(title)),
      );

  /// Backfill language metadata for a legacy book (imported before v8).
  Future<void> backfillLanguage(
    int bookId,
    String? language,
    String? pageProgressionDirection,
    String? primaryWritingMode,
  ) =>
      (_db.update(_db.books)..where((t) => t.id.equals(bookId))).write(
        BooksCompanion(
          language: Value(language),
          pageProgressionDirection: Value(pageProgressionDirection),
          primaryWritingMode: Value(primaryWritingMode),
        ),
      );

  /// Save per-book display overrides (verticalText and readingDirection).
  ///
  /// Pass `null` to clear an override and revert to the book's default.
  Future<void> updateDisplayOverrides(
    int bookId, {
    required bool? verticalText,
    required String? readingDirection,
  }) =>
      (_db.update(_db.books)..where((t) => t.id.equals(bookId))).write(
        BooksCompanion(
          overrideVerticalText: Value(verticalText),
          overrideReadingDirection: Value(readingDirection),
        ),
      );

  /// Update the cover image path (custom cover).
  Future<void> updateCoverImagePath(int bookId, String? path) =>
      (_db.update(_db.books)..where((t) => t.id.equals(bookId))).write(
        BooksCompanion(coverImagePath: Value(path)),
      );

  // ──────────────── Delete ────────────────

  /// Delete a book and its extracted files.
  Future<void> deleteBook(int bookId) async {
    final book = await getBookById(bookId);
    if (book != null) {
      // Delete extracted files
      final contentDir = Directory(book.filePath);
      if (await contentDir.exists()) {
        // Go up one level to delete the entire book directory
        final bookDir = contentDir.parent;
        await bookDir.delete(recursive: true);
      }
    }

    await (_db.delete(_db.books)..where((t) => t.id.equals(bookId))).go();
  }
}
