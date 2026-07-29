import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:mekuru/core/platform/android_saf_service.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/utils/atomic_file.dart';
import 'package:mekuru/features/library/data/services/epub_parser.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/data/services/cbz_parser.dart';
import 'package:mekuru/features/manga/data/services/mokuro_parser.dart';
import 'package:mekuru/features/manga/data/services/mokuro_word_segmenter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Repository for book CRUD operations and EPUB import.
class BookRepository {
  final AppDatabase _db;
  static const String originalMokuroOcrBackupFileName =
      'pages_cache.original_mokuro.json';
  static const _uuid = Uuid();

  BookRepository(this._db);

  /// Collision-proof directory name for an imported book: a sortable
  /// timestamp plus a random suffix, so concurrent or rapid imports (e.g.
  /// batch import) can never claim the same directory.
  @visibleForTesting
  static String uniqueImportDirName(String prefix) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final suffix = _uuid.v4().substring(0, 8);
    return '${prefix}_${timestamp}_$suffix';
  }

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

    final bookDir = Directory(
      p.join(booksDir.path, uniqueImportDirName('book')),
    );
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
      AndroidSafFailure? readFailure;
      final bytes = await AndroidSafService.readBytesFromTreePath(
        safTreeUri,
        safSelectedFileRelativePath,
        onFailure: (failure) => readFailure = failure,
      );
      if (bytes == null) {
        throw Exception(
          'Could not read selected file from folder access grant:\n'
          '$safSelectedFileRelativePath'
          '${readFailure == null ? '' : '\n$readFailure'}',
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

      return _importManifestWithPages(parsed.$1, parsed.$2);
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
  Future<Book> importCbz(
    String sourcePath, {
    void Function(double progress)? onProgress,
  }) async {
    final appDir = await getApplicationSupportDirectory();
    final booksDir = Directory(p.join(appDir.path, 'books'));
    final cacheDir = Directory(
      p.join(booksDir.path, uniqueImportDirName('manga')),
    );
    await cacheDir.create(recursive: true);

    // Extract the archive, which also reports each page's dimensions from the
    // bytes it already holds — no second pass over the extracted files.
    final cbzMeta = await CbzParser.extract(
      sourcePath,
      cacheDir.path,
      onProgress: onProgress,
    );

    // Build MokuroPages with empty blocks (no OCR yet).
    final fileNames = cbzMeta.imageFileNames;
    final pages = <MokuroPage>[
      for (var i = 0; i < fileNames.length; i++)
        MokuroPage(
          pageIndex: i,
          imageFileName: fileNames[i],
          imgWidth: cbzMeta.dimensionsOf(fileNames[i])?.width ?? 0,
          imgHeight: cbzMeta.dimensionsOf(fileNames[i])?.height ?? 0,
          blocks: const [],
        ),
    ];

    // Build and save pages_cache.json
    final mokuroBook = MokuroBook(
      title: cbzMeta.title,
      imageDirPath: cbzMeta.imageDirPath,
      ocrCompleted: false,
      pages: pages,
    );
    final cacheFile = File(p.join(cacheDir.path, 'pages_cache.json'));
    await writeStringAtomic(cacheFile, jsonEncode(mokuroBook.toJson()));

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
  ) async {
    final appDir = await getApplicationSupportDirectory();
    final booksDir = Directory(p.join(appDir.path, 'books'));

    final cacheDir = Directory(
      p.join(booksDir.path, uniqueImportDirName('manga')),
    );
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
      ocrSource: 'mokuro',
      ocrCompleted: true,
      pages: pages,
    );
    final cacheJson = jsonEncode(mokuroBook.toJson());
    final cacheFile = File(p.join(cacheDir.path, 'pages_cache.json'));
    await writeStringAtomic(cacheFile, cacheJson);
    final originalBackupFile = File(
      p.join(cacheDir.path, originalMokuroOcrBackupFileName),
    );
    await writeStringAtomic(originalBackupFile, cacheJson);

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
  /// Save per-book display overrides (verticalText, readingDirection,
  /// and furiganaMode).
  ///
  /// Pass `null` to clear an override and revert to the book's default.
  Future<void> updateDisplayOverrides(
    int bookId, {
    required bool? verticalText,
    required String? readingDirection,
    Value<String?> furiganaMode = const Value.absent(),
  }) => (_db.update(_db.books)..where((t) => t.id.equals(bookId))).write(
    BooksCompanion(
      overrideVerticalText: Value(verticalText),
      overrideReadingDirection: Value(readingDirection),
      furiganaMode: furiganaMode,
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
  /// Reads the cached page data, runs [MokuroWordSegmenter.segmentAllPages]
  /// to re-segment (it replaces each block's words wholesale), and writes
  /// back the updated cache.
  Future<void> reprocessMangaOcr(Book book) async {
    if (book.bookType != 'manga') return;

    final cacheFile = File(p.join(book.filePath, 'pages_cache.json'));
    if (!await cacheFile.exists()) {
      throw Exception('Pages cache not found. Try re-importing this manga.');
    }

    final content = await cacheFile.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;
    final mokuroBook = MokuroBook.fromJson(json);

    // Re-run segmentation. Existing contentBounds (if any) are preserved by
    // MokuroPage.copyWith through the segmentation pipeline. No need to
    // strip existing words first: segmentation replaces them wholesale, and
    // if MeCab is unavailable the pages come back untouched (keeping the
    // current words is strictly better than wiping them).
    final resegmented = await MokuroWordSegmenter.segmentAllPages(
      mokuroBook.pages,
    );

    // Write back
    final updated = MokuroBook(
      title: mokuroBook.title,
      imageDirPath: mokuroBook.imageDirPath,
      safTreeUri: mokuroBook.safTreeUri,
      safImageDirRelativePath: mokuroBook.safImageDirRelativePath,
      autoCropVersion: mokuroBook.autoCropVersion,
      ocrSource: mokuroBook.ocrSource,
      ocrCompleted: mokuroBook.ocrCompleted,
      pages: resegmented,
    );
    await writeStringAtomic(cacheFile, jsonEncode(updated.toJson()));

    debugPrint(
      '[MangaOCR] Reprocessed ${resegmented.length} pages for "${book.title}"',
    );
  }

  Future<void> backupOriginalMokuroOcrIfNeeded(Book book) async {
    if (book.bookType != 'manga') return;

    final cacheFile = File(p.join(book.filePath, 'pages_cache.json'));
    if (!await cacheFile.exists()) {
      throw Exception('Pages cache not found. Try re-importing this manga.');
    }

    final backupFile = File(
      p.join(book.filePath, originalMokuroOcrBackupFileName),
    );
    if (await backupFile.exists()) {
      return;
    }

    final content = await cacheFile.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;
    final mokuroBook = MokuroBook.fromJson(json);
    if (mokuroBook.ocrSource != 'mokuro') {
      return;
    }

    await writeStringAtomic(backupFile, content);
    debugPrint('[MangaOCR] Backed up original Mokuro OCR for "${book.title}"');
  }

  Future<bool> restoreOriginalMokuroOcr(Book book) async {
    if (book.bookType != 'manga') return false;

    final cacheFile = File(p.join(book.filePath, 'pages_cache.json'));
    if (!await cacheFile.exists()) {
      throw Exception('Pages cache not found. Try re-importing this manga.');
    }

    final backupFile = File(
      p.join(book.filePath, originalMokuroOcrBackupFileName),
    );
    if (!await backupFile.exists()) {
      return false;
    }

    final content = await backupFile.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;
    MokuroBook.fromJson(json); // Validate the backup before restoring it.

    await writeStringAtomic(cacheFile, content);
    debugPrint('[MangaOCR] Restored original Mokuro OCR for "${book.title}"');
    return true;
  }

  /// Remove OCR data from all pages in a manga cache file.
  ///
  /// Keeps page metadata (image dimensions, content bounds) and clears only
  /// OCR text blocks/word overlays so OCR can be run again from scratch.
  Future<void> clearMangaOcr(Book book) async {
    if (book.bookType != 'manga') return;

    final cacheFile = File(p.join(book.filePath, 'pages_cache.json'));
    if (!await cacheFile.exists()) {
      throw Exception('Pages cache not found. Try re-importing this manga.');
    }

    final content = await cacheFile.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;
    final mokuroBook = MokuroBook.fromJson(json);

    final clearedPages = mokuroBook.pages
        .map((page) => page.copyWith(blocks: const []))
        .toList();

    final updated = MokuroBook(
      title: mokuroBook.title,
      imageDirPath: mokuroBook.imageDirPath,
      safTreeUri: mokuroBook.safTreeUri,
      safImageDirRelativePath: mokuroBook.safImageDirRelativePath,
      autoCropVersion: mokuroBook.autoCropVersion,
      ocrSource: null,
      ocrCompleted: false,
      pages: clearedPages,
    );

    await writeStringAtomic(cacheFile, jsonEncode(updated.toJson()));
    debugPrint('[MangaOCR] Cleared OCR for "${book.title}"');
  }

  /// Compute and cache auto-crop bounds on demand for a manga book.
  ///
  /// Returns `true` if bounds were computed and cache was updated.
  /// Returns `false` if bounds already existed (no work performed).
  Future<bool> ensureMangaAutoCropComputed(
    Book book, {
    bool force = false,
    int whiteThreshold = 240,
  }) async {
    if (book.bookType != 'manga') return false;

    final cacheFile = File(p.join(book.filePath, 'pages_cache.json'));
    if (!await cacheFile.exists()) {
      throw Exception('Pages cache not found. Try re-importing this manga.');
    }

    final content = await cacheFile.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;
    final mokuroBook = MokuroBook.fromJson(json);

    if (!force &&
        mokuroBook.autoCropVersion >= MokuroBook.currentAutoCropVersion) {
      return false;
    }

    final withBounds =
        mokuroBook.safTreeUri != null &&
            mokuroBook.safImageDirRelativePath != null
        ? await MokuroParser.computeAllContentBoundsSaf(
            mokuroBook.pages,
            mokuroBook.safTreeUri!,
            mokuroBook.safImageDirRelativePath!,
            whiteThreshold: whiteThreshold,
          )
        : await MokuroParser.computeAllContentBounds(
            mokuroBook.pages,
            mokuroBook.imageDirPath,
            whiteThreshold: whiteThreshold,
          );

    final updated = MokuroBook(
      title: mokuroBook.title,
      imageDirPath: mokuroBook.imageDirPath,
      safTreeUri: mokuroBook.safTreeUri,
      safImageDirRelativePath: mokuroBook.safImageDirRelativePath,
      autoCropVersion: MokuroBook.currentAutoCropVersion,
      ocrSource: mokuroBook.ocrSource,
      ocrCompleted: mokuroBook.ocrCompleted,
      pages: withBounds,
    );

    await writeStringAtomic(cacheFile, jsonEncode(updated.toJson()));
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
