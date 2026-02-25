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

/// Result of importing mokuro manga, with an optional warning message.
class MangaImportResult {
  final List<Book> books;
  final String? warning;

  const MangaImportResult(this.books, {this.warning});
}

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

  /// Import mokuro manga books from a directory.
  ///
  /// Prefers `.mokuro` JSON files (v0.2+) when present. Falls back to the
  /// legacy format (HTML + `_ocr/` directory) otherwise. If both formats
  /// are found, the `.mokuro` file is used and a warning is returned.
  ///
  /// Returns a [MangaImportResult] with the imported books and an optional
  /// warning message.
  Future<MangaImportResult> importMokuroDirectory(String dirPath) async {
    // Scan for .mokuro files
    final mokuroFiles = <File>[];
    bool hasLegacyOcr = false;
    try {
      await for (final entity in Directory(dirPath).list()) {
        if (entity is File && entity.path.endsWith('.mokuro')) {
          mokuroFiles.add(entity);
        }
        if (entity is Directory && p.basename(entity.path) == '_ocr') {
          hasLegacyOcr = true;
        }
      }
    } catch (e) {
      throw Exception('Cannot read directory: $dirPath\n$e');
    }

    if (mokuroFiles.isNotEmpty) {
      // ── Use .mokuro JSON format ──
      String? warning;
      if (hasLegacyOcr) {
        warning = 'Note: legacy _ocr/ folder was found but ignored '
            'in favor of .mokuro file.';
        debugPrint('[MangaImport] $warning');
      }

      final importedBooks = <Book>[];
      for (int i = 0; i < mokuroFiles.length; i++) {
        final book = await _importSingleMokuroFile(mokuroFiles[i].path, i);
        importedBooks.add(book);
      }

      if (importedBooks.isEmpty) {
        throw Exception('No manga could be imported from .mokuro files.');
      }

      return MangaImportResult(importedBooks, warning: warning);
    }

    // ── Fall back to legacy format (HTML + _ocr/) ──
    final manifests = await MokuroParser.parseMokuroDirectory(dirPath);
    if (manifests.isEmpty) {
      throw Exception('No mokuro books found in this directory.');
    }

    final importedBooks = <Book>[];
    for (int i = 0; i < manifests.length; i++) {
      final book = await _importFromLegacyManifest(manifests[i], i);
      importedBooks.add(book);
    }

    return MangaImportResult(importedBooks);
  }

  /// Import a single `.mokuro` JSON file into the library.
  Future<Book> _importSingleMokuroFile(
    String mokuroFilePath,
    int index,
  ) async {
    final (manifest, parsedPages) =
        await MokuroParser.parseMokuroFile(mokuroFilePath);
    return _importManifestWithPages(manifest, parsedPages, index);
  }

  /// Import from a legacy manifest (HTML + _ocr/).
  Future<Book> _importFromLegacyManifest(
    MokuroBookManifest manifest,
    int index,
  ) async {
    final pages = await MokuroParser.parseAllPages(
      manifest.ocrDirPath,
      manifest.imageDirPath,
      manifest.imageFileNames,
    );
    return _importManifestWithPages(manifest, pages, index);
  }

  /// Shared import logic: segment words, save cache, insert into DB.
  Future<Book> _importManifestWithPages(
    MokuroBookManifest manifest,
    List<MokuroPage> rawPages,
    int index,
  ) async {
    final appDir = await getApplicationSupportDirectory();
    final booksDir = Directory(p.join(appDir.path, 'books'));

    final timestamp = DateTime.now().millisecondsSinceEpoch + index;
    final cacheDir = Directory(p.join(booksDir.path, 'manga_$timestamp'));
    await cacheDir.create(recursive: true);

    // Segment words using MeCab
    final pages = await MokuroWordSegmenter.segmentAllPages(rawPages);

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

  // ──────────────── Manga OCR ────────────────

  /// Re-run MeCab word segmentation on an existing manga book.
  ///
  /// Reads the cached page data, strips existing words from all blocks,
  /// runs [MokuroWordSegmenter.segmentAllPages] to re-segment, and
  /// writes back the updated cache.
  Future<void> reprocessMangaOcr(Book book) async {
    if (book.bookType != 'manga') return;

    final cacheFile = File(p.join(book.filePath, 'pages_cache.json'));
    if (!await cacheFile.exists()) {
      throw Exception('Pages cache not found. Try re-importing this manga.');
    }

    final content = await cacheFile.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;
    final mokuroBook = MokuroBook.fromJson(json);

    // Strip existing words from all blocks
    final strippedPages = mokuroBook.pages.map((page) {
      return page.copyWith(
        blocks: page.blocks.map((block) {
          return block.copyWith(words: []);
        }).toList(),
      );
    }).toList();

    // Re-run segmentation
    final resegmented =
        await MokuroWordSegmenter.segmentAllPages(strippedPages);

    // Write back
    final updated = MokuroBook(
      title: mokuroBook.title,
      imageDirPath: mokuroBook.imageDirPath,
      pages: resegmented,
    );
    await cacheFile.writeAsString(jsonEncode(updated.toJson()));

    debugPrint(
      '[MangaOCR] Reprocessed ${resegmented.length} pages for "${book.title}"',
    );
  }

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
