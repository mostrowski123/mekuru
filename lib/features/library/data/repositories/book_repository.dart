import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:mekuru/core/platform/android_saf_service.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/library/data/services/epub_parser.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/data/services/cbz_parser.dart';
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
  Future<Book?> getMostRecentlyReadBook() =>
      (_db.select(_db.books)
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
            pageProgressionDirection: metadata.pageProgressionDirection != null
                ? Value(metadata.pageProgressionDirection)
                : const Value.absent(),
            primaryWritingMode: metadata.primaryWritingMode != null
                ? Value(metadata.primaryWritingMode)
                : const Value.absent(),
          ),
        );

    return (await getBookById(bookId))!;
  }

  /// Import a manga book from a `.mokuro` or `.html` file.
  ///
  /// [filePath] is the original file location (used to derive the image
  /// directory path). [cachedFilePath] is an optional alternative path
  /// where the file content can be read from (e.g. a cache copy on Android
  /// where pickFiles() copies the selected file to cache).
  ///
  /// Returns the created [Book].
  Future<Book> importMangaFromFile(
    String filePath, {
    String? cachedFilePath,
    String? safTreeUri,
    String? safSelectedFileRelativePath,
  }) async {
    debugPrint('[MangaImport] importMangaFromFile called with: $filePath');
    if (cachedFilePath != null && cachedFilePath != filePath) {
      debugPrint('[MangaImport] Reading content from cached: $cachedFilePath');
    }
    if (safTreeUri != null) {
      debugPrint(
        '[MangaImport] SAF enabled tree=$safTreeUri '
        'fileRel=$safSelectedFileRelativePath',
      );
    }

    final ext = p.extension(filePath).toLowerCase();
    // Read file content from the cached path if available (Android file
    // picker), otherwise from the original path (desktop/iOS). For folder-
    // first SAF imports, copy only the selected .mokuro/.html file to a temp
    // file so the parser can read it locally while images/OCR stay in place.
    var readPath = cachedFilePath ?? filePath;
    String? tempReadPath;

    if (safTreeUri != null &&
        safSelectedFileRelativePath != null &&
        cachedFilePath == null) {
      final bytes = await AndroidSafService.readBytesFromTreePath(
        safTreeUri,
        safSelectedFileRelativePath,
      );
      if (bytes == null) {
        throw Exception(
          'Could not read selected file from folder access grant:\n'
          '$safSelectedFileRelativePath',
        );
      }

      final tmpDir = await getTemporaryDirectory();
      final tmpName =
          'manga_import_${DateTime.now().microsecondsSinceEpoch}$ext';
      tempReadPath = p.join(tmpDir.path, tmpName);
      await File(tempReadPath).writeAsBytes(bytes, flush: true);
      readPath = tempReadPath;
    }

    final (MokuroBookManifest, List<MokuroPage>) parsed;
    try {
      if (ext == '.mokuro') {
        parsed = await MokuroParser.parseMokuroFile(
          readPath,
          originalDirPath: cachedFilePath != null ? p.dirname(filePath) : null,
          safTreeUri: safTreeUri,
          safSelectedFileRelativePath: safSelectedFileRelativePath,
        );
      } else if (ext == '.html') {
        parsed = await MokuroParser.parseSingleHtmlFile(
          readPath,
          originalDirPath: cachedFilePath != null ? p.dirname(filePath) : null,
          safTreeUri: safTreeUri,
          safSelectedFileRelativePath: safSelectedFileRelativePath,
        );
      } else {
        throw Exception(
          'Unsupported file type: $ext\n'
          'Expected a .mokuro or .html file.',
        );
      }

      return _importManifestWithPages(parsed.$1, parsed.$2, 0);
    } finally {
      if (tempReadPath != null) {
        try {
          final tmp = File(tempReadPath);
          if (await tmp.exists()) {
            await tmp.delete();
          }
        } catch (_) {
          // Best-effort temp cleanup only.
        }
      }
    }
  }

  /// Import a CBZ (Comic Book ZIP) archive into the library.
  ///
  /// Extracts images from the archive, reads dimensions for each page,
  /// and creates a manga book with empty text blocks (no OCR data yet).
  /// OCR can be run later as a separate step.
  ///
  /// Returns the created [Book].
  Future<Book> importCbz(String sourcePath) async {
    final appDir = await getApplicationSupportDirectory();
    final booksDir = Directory(p.join(appDir.path, 'books'));
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final cacheDir = Directory(p.join(booksDir.path, 'manga_$timestamp'));
    await cacheDir.create(recursive: true);

    // Extract CBZ archive to cache directory
    final cbzMeta = await CbzParser.extract(sourcePath, cacheDir.path);

    // Build MokuroPages with empty blocks (no OCR yet).
    // Read image dimensions from each extracted file.
    final pages = <MokuroPage>[];
    for (var i = 0; i < cbzMeta.imageFileNames.length; i++) {
      final fileName = cbzMeta.imageFileNames[i];
      final imagePath = p.join(cbzMeta.imageDirPath, fileName);
      final dims = await CbzParser.readImageDimensions(imagePath);

      pages.add(MokuroPage(
        pageIndex: i,
        imageFileName: fileName,
        imgWidth: dims?.width ?? 0,
        imgHeight: dims?.height ?? 0,
        blocks: const [],
      ));
    }

    // Build and save pages_cache.json
    final mokuroBook = MokuroBook(
      title: cbzMeta.title,
      imageDirPath: cbzMeta.imageDirPath,
      pages: pages,
    );
    final cacheFile = File(p.join(cacheDir.path, 'pages_cache.json'));
    await cacheFile.writeAsString(jsonEncode(mokuroBook.toJson()));

    debugPrint(
      '[CbzImport] Cached ${pages.length} pages for "${cbzMeta.title}"',
    );

    // Insert into database
    final bookId = await _db
        .into(_db.books)
        .insert(
          BooksCompanion.insert(
            title: cbzMeta.title,
            filePath: cacheDir.path,
            bookType: const Value('manga'),
            coverImagePath: cbzMeta.coverImagePath != null
                ? Value(cbzMeta.coverImagePath)
                : const Value.absent(),
            totalPages: Value(pages.length),
          ),
        );

    return (await getBookById(bookId))!;
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
    final segmented = await MokuroWordSegmenter.segmentAllPages(rawPages);

    // Auto-crop bounds are now computed lazily the first time the user enables
    // auto-crop for this manga. Import stores segmented OCR only.
    final pages = segmented;

    // Build and save pages_cache.json
    final mokuroBook = MokuroBook(
      title: manifest.title,
      imageDirPath: manifest.imageDirPath,
      safTreeUri: manifest.safTreeUri,
      safImageDirRelativePath: manifest.safImageDirRelativePath,
      pages: pages,
    );
    final cacheFile = File(p.join(cacheDir.path, 'pages_cache.json'));
    await cacheFile.writeAsString(jsonEncode(mokuroBook.toJson()));

    debugPrint(
      '[MangaImport] Cached ${pages.length} pages for "${manifest.title}"',
    );

    // Cover = alphabetically first image file (ASCII sort).
    // The mokuro page order doesn't always start with the cover —
    // filenames like _01.jpg or 000.jpg may precede numbered pages.
    String? coverImagePath;
    if (manifest.imageFileNames.isNotEmpty) {
      const imageExtensions = {
        '.jpg',
        '.jpeg',
        '.png',
        '.gif',
        '.webp',
        '.bmp',
        '.tiff',
        '.tif',
      };
      final sorted = [...manifest.imageFileNames]..sort();
      for (final fileName in sorted) {
        final ext = p.extension(fileName).toLowerCase();
        if (!imageExtensions.contains(ext)) continue;
        if (manifest.safTreeUri != null &&
            manifest.safImageDirRelativePath != null) {
          final relPath = p.posix.join(
            manifest.safImageDirRelativePath!,
            fileName,
          );
          final exists = await AndroidSafService.existsInTreePath(
            manifest.safTreeUri!,
            relPath,
          );
          if (!exists) continue;

          final uri = await AndroidSafService.getDocumentUriInTree(
            manifest.safTreeUri!,
            relPath,
          );
          if (uri != null) {
            coverImagePath = uri;
            break;
          }
        } else {
          final candidatePath = p.join(manifest.imageDirPath, fileName);
          if (await File(candidatePath).exists()) {
            coverImagePath = candidatePath;
            break;
          }
        }
      }
    }

    // Insert into database
    final bookId = await _db
        .into(_db.books)
        .insert(
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
          readProgress: progress != null
              ? Value(progress)
              : const Value.absent(),
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
  ) => (_db.update(_db.books)..where((t) => t.id.equals(bookId))).write(
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
  }) => (_db.update(_db.books)..where((t) => t.id.equals(bookId))).write(
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

    // Re-run segmentation. Existing contentBounds (if any) are preserved by
    // MokuroPage.copyWith through the segmentation pipeline.
    final resegmented = await MokuroWordSegmenter.segmentAllPages(
      strippedPages,
    );

    // Write back
    final updated = MokuroBook(
      title: mokuroBook.title,
      imageDirPath: mokuroBook.imageDirPath,
      safTreeUri: mokuroBook.safTreeUri,
      safImageDirRelativePath: mokuroBook.safImageDirRelativePath,
      pages: resegmented,
    );
    await cacheFile.writeAsString(jsonEncode(updated.toJson()));

    debugPrint(
      '[MangaOCR] Reprocessed ${resegmented.length} pages for "${book.title}"',
    );
  }

  /// Compute and cache auto-crop bounds on demand for a manga book.
  ///
  /// Returns `true` if bounds were computed and cache was updated.
  /// Returns `false` if bounds already existed (no work performed).
  Future<bool> ensureMangaAutoCropComputed(Book book) async {
    if (book.bookType != 'manga') return false;

    final cacheFile = File(p.join(book.filePath, 'pages_cache.json'));
    if (!await cacheFile.exists()) {
      throw Exception('Pages cache not found. Try re-importing this manga.');
    }

    final content = await cacheFile.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;
    final mokuroBook = MokuroBook.fromJson(json);

    if (mokuroBook.pages.any((p) => p.contentBounds != null)) {
      return false;
    }

    final withBounds =
        mokuroBook.safTreeUri != null &&
            mokuroBook.safImageDirRelativePath != null
        ? await MokuroParser.computeAllContentBoundsSaf(
            mokuroBook.pages,
            mokuroBook.safTreeUri!,
            mokuroBook.safImageDirRelativePath!,
          )
        : await MokuroParser.computeAllContentBounds(
            mokuroBook.pages,
            mokuroBook.imageDirPath,
          );

    final updated = MokuroBook(
      title: mokuroBook.title,
      imageDirPath: mokuroBook.imageDirPath,
      safTreeUri: mokuroBook.safTreeUri,
      safImageDirRelativePath: mokuroBook.safImageDirRelativePath,
      pages: withBounds,
    );

    await cacheFile.writeAsString(jsonEncode(updated.toJson()));
    debugPrint(
      '[MangaAutoCrop] Computed bounds for ${withBounds.length} pages '
      'for "${book.title}"',
    );
    return true;
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
    await (_db.delete(
      _db.bookmarks,
    )..where((t) => t.bookId.equals(bookId))).go();
    await (_db.delete(
      _db.highlights,
    )..where((t) => t.bookId.equals(bookId))).go();

    await (_db.delete(_db.books)..where((t) => t.id.equals(bookId))).go();
  }
}
