import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/library/data/services/epub_parser.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/data/services/mokuro_parser.dart';
import 'package:mekuru/features/manga/data/services/mokuro_word_segmenter.dart';
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

  /// Import all mokuro manga books from a directory.
  ///
  /// Discovers all `.html` files in [dirPath], parses OCR data,
  /// segments words via MeCab, and saves processed cache files.
  ///
  /// Returns the list of created [Book] entries.
  Future<List<Book>> importMokuroDirectory(String dirPath) async {
    final manifests = await MokuroParser.parseMokuroDirectory(dirPath);
    if (manifests.isEmpty) {
      throw Exception('No mokuro books found in this directory.');
    }

    final appDir = await getApplicationSupportDirectory();
    final booksDir = Directory(p.join(appDir.path, 'books'));

    final importedBooks = <Book>[];

    for (int i = 0; i < manifests.length; i++) {
      final manifest = manifests[i];

      // Create cache directory
      final timestamp = DateTime.now().millisecondsSinceEpoch + i;
      final cacheDir = Directory(p.join(booksDir.path, 'manga_$timestamp'));
      await cacheDir.create(recursive: true);

      // Parse OCR data for all pages
      var pages = await MokuroParser.parseAllPages(
        manifest.ocrDirPath,
        manifest.imageDirPath,
        manifest.imageFileNames,
      );

      // Segment words using MeCab
      pages = await MokuroWordSegmenter.segmentAllPages(pages);

      // Build and save pages_cache.json
      final mokuroBook = MokuroBook(
        title: manifest.title,
        imageDirPath: manifest.imageDirPath,
        pages: pages,
      );
      final cacheFile = File(p.join(cacheDir.path, 'pages_cache.json'));
      await cacheFile.writeAsString(jsonEncode(mokuroBook.toJson()));

      debugPrint(
        '[MangaImport] Cached ${pages.length} pages for "${manifest.title}"',
      );

      // Cover = first page image
      String? coverImagePath;
      if (manifest.imageFileNames.isNotEmpty) {
        final coverPath = p.join(
          manifest.imageDirPath,
          manifest.imageFileNames.first,
        );
        if (await File(coverPath).exists()) {
          coverImagePath = coverPath;
        }
      }

      // Insert into database
      final bookId = await _db.into(_db.books).insert(
            BooksCompanion.insert(
              title: manifest.title,
              filePath: cacheDir.path,
              bookType: const Value('manga'),
              coverImagePath: coverImagePath != null
                  ? Value(coverImagePath)
                  : const Value.absent(),
              totalPages: Value(pages.length),
            ),
          );

      importedBooks.add((await getBookById(bookId))!);
    }

    return importedBooks;
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

  /// Delete a book and its cached/extracted files.
  ///
  /// For EPUB: deletes the entire book directory (copied files).
  /// For manga: deletes only the cache directory. Original images are
  /// kept since they belong to the user.
  Future<void> deleteBook(int bookId) async {
    final book = await getBookById(bookId);
    if (book != null) {
      if (book.bookType == 'manga') {
        // filePath IS the cache directory — delete it directly.
        final cacheDir = Directory(book.filePath);
        if (await cacheDir.exists()) {
          await cacheDir.delete(recursive: true);
        }
      } else {
        // EPUB: filePath is the content dir, parent is the book dir.
        final contentDir = Directory(book.filePath);
        if (await contentDir.exists()) {
          final bookDir = contentDir.parent;
          await bookDir.delete(recursive: true);
        }
      }
    }

    // Clean up bookmarks and highlights for this book
    await (_db.delete(_db.bookmarks)..where((t) => t.bookId.equals(bookId)))
        .go();
    await (_db.delete(_db.highlights)..where((t) => t.bookId.equals(bookId)))
        .go();

    await (_db.delete(_db.books)..where((t) => t.id.equals(bookId))).go();
  }
}
