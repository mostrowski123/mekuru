import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:mekuru/core/platform/android_saf_service.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/core/utils/atomic_file.dart';
import 'package:mekuru/features/library/data/services/epub_manga_converter.dart';
import 'package:mekuru/features/library/data/services/epub_parser.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/data/services/cbz_parser.dart';
import 'package:mekuru/features/manga/data/services/manga_cbz_export.dart';
import 'package:mekuru/features/manga/data/services/mokuro_parser.dart';
import 'package:mekuru/features/manga/data/services/mokuro_word_segmenter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// compute() entry point: (epubPath, extractDir) → parsed metadata.
Future<EpubMetadata> _parseEpubForImport((String, String) args) =>
    EpubParser.parseEpub(args.$1, args.$2);

/// compute() entry point: (cacheDir, outPath) → written page count.
Future<int> _writeCbzForExport((String, String) args) =>
    writeCbz(args.$1, args.$2);

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

  /// Dir names currently being populated by an import. The orphan sweep must
  /// never touch these, regardless of any other signal — the name-timestamp
  /// age gate alone would miss an import that straddles a forward clock jump
  /// (e.g. an NTP sync), and must stay safe if [sweepOrphanImportDirs] is
  /// ever called with a smaller `minAge`.
  @visibleForTesting
  static final inFlightImportDirNames = <String>{};

  /// Matches every naming era of import dirs — `<prefix>_<ms>` with an
  /// optional `_<uuid8>` suffix (added later for batch-import collisions) —
  /// capturing the creation timestamp in group 1.
  @visibleForTesting
  static final importDirName = RegExp(
    r'^(?:book|manga)_(\d+)(?:_[0-9a-f]{8})?$',
  );

  static const _booksSegment = 'books';

  /// The single root every import dir lives under. Keep [_booksSegment] and
  /// this helper the only spellings of the layout — [claimedDirNames] must
  /// always look for the same segment the writer creates.
  static Future<Directory> _booksRootDir() async {
    final appDir = await getApplicationSupportDirectory();
    return Directory(p.join(appDir.path, _booksSegment));
  }

  /// Dir names under a `books` path segment that [path] claims — every
  /// occurrence, never the absolute prefix, because stored paths go stale
  /// when Android restores the app into a different data directory.
  @visibleForTesting
  static Iterable<String> claimedDirNames(String path) sync* {
    final parts = p.split(p.normalize(path));
    for (var i = 0; i < parts.length - 1; i++) {
      if (parts[i] == _booksSegment) yield parts[i + 1];
    }
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

  /// Creates a fresh import directory under app storage, runs [body] in it,
  /// and deletes the directory (recursive, best-effort) if [body] throws, so
  /// a failed import never strands a partial copy/extraction in app storage.
  Future<T> _inNewImportDir<T>(
    String prefix,
    Future<T> Function(Directory dir) body,
  ) async {
    final name = uniqueImportDirName(prefix);
    final dir = Directory(p.join((await _booksRootDir()).path, name));
    inFlightImportDirNames.add(name);
    try {
      await dir.create(recursive: true);
      return await body(dir);
    } catch (_) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {
        // Best-effort only — the OS may still hold file locks (Windows).
      }
      rethrow;
    } finally {
      inFlightImportDirNames.remove(name);
    }
  }

  /// Import an EPUB file into the library.
  ///
  /// 1. Copies the EPUB to app storage
  /// 2. Unzips and parses metadata
  /// 3. Extracts cover image
  /// 4. Creates a Book entry in the database
  ///
  /// Returns the created [Book].
  Future<Book> importEpub(String sourcePath) async {
    // Reject over-cap files before the copy below — a rejected import must
    // not strand a full-size copy in app storage (Sentry MEKURU-1D).
    await EpubParser.ensureWithinSizeCap(File(sourcePath));

    return _inNewImportDir('book', (bookDir) async {
      // Copy EPUB to app storage
      final epubFileName = p.basename(sourcePath);
      final storedEpubPath = p.join(bookDir.path, epubFileName);
      await File(sourcePath).copy(storedEpubPath);

      // Unzip to a subdirectory
      final extractDir = p.join(bookDir.path, 'content');
      await Directory(extractDir).create(recursive: true);

      // Parse EPUB metadata — extraction inflates up to the whole book, so
      // keep it off the UI isolate.
      final metadata = await compute(_parseEpubForImport, (
        storedEpubPath,
        extractDir,
      ));

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
              hasVerticalCss: Value(metadata.hasVerticalCss),
            ),
          );

      return (await getBookById(bookId))!;
    });
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

      return await _importManifestWithPages(parsed.$1, parsed.$2);
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
    return _inNewImportDir('manga', (cacheDir) async {
      // Extract the archive, which also reports each page's dimensions from
      // the bytes it already holds — no second pass over the extracted files.
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
      final cacheFile = File(p.join(cacheDir.path, mangaPagesCacheFileName));
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
    });
  }

  /// Convert an imported image-only (fixed-layout) EPUB into a manga book,
  /// in place on the same Books row.
  Future<Book> convertEpubToManga(Book book) async {
    if (book.bookType != 'epub') {
      throw ArgumentError('Only EPUB books can be converted, got $book');
    }
    final contentDir = book.filePath;
    if (!await Directory(contentDir).exists()) {
      throw FileSystemException(
        'EPUB content is missing — re-import the book',
        contentDir,
      );
    }
    final bookDir = p.dirname(contentDir);

    // Spine scanning and the image moves touch every page file — keep them
    // off the UI isolate. Throws EpubNotMangaException for non-manga EPUBs.
    final pages = await compute(applyEpubMangaConversion, (
      contentDir,
      bookDir,
    ));

    final imageDirPath = p.join(bookDir, 'images');
    final mokuroBook = MokuroBook(
      title: book.title,
      imageDirPath: imageDirPath,
      ocrCompleted: false,
      pages: pages,
    );
    await writeStringAtomic(
      File(p.join(bookDir, mangaPagesCacheFileName)),
      jsonEncode(mokuroBook.toJson()),
    );

    // Only after the manga payload is fully on disk does the row flip; the
    // stale epub reading position is meaningless for a page-based book.
    await (_db.update(_db.books)..where((t) => t.id.equals(book.id))).write(
      BooksCompanion(
        bookType: const Value('manga'),
        filePath: Value(bookDir),
        coverImagePath: Value(p.join(imageDirPath, pages.first.imageFileName)),
        totalPages: Value(pages.length),
        lastReadCfi: const Value(null),
        readProgress: const Value(0.0),
      ),
    );

    // Best-effort cleanup of the now-unused EPUB payload; a failure here
    // leaves dead bytes that deleteBook removes later, never a broken book.
    try {
      await Directory(contentDir).delete(recursive: true);
    } catch (_) {}
    try {
      await for (final entry in Directory(bookDir).list()) {
        if (entry is File && p.extension(entry.path).toLowerCase() == '.epub') {
          await entry.delete();
        }
      }
    } catch (_) {}

    return (await getBookById(book.id))!;
  }

  /// Build a CBZ of [book]'s pages in a temp file named [fileName].
  ///
  /// Returns the temp file path and the number of pages written. The caller
  /// owns sharing and deleting the file. Throws [EmptyMangaExportException]
  /// or [SafMangaExportUnsupportedException] for books that cannot export.
  Future<(String, int)> exportMangaCbz(
    Book book, {
    required String fileName,
  }) async {
    if (book.bookType != 'manga') {
      throw ArgumentError('Only manga books can be exported, got $book');
    }
    final outPath = p.join((await getTemporaryDirectory()).path, fileName);
    // The zip streams every page file — keep it off the UI isolate.
    final pageCount = await compute(_writeCbzForExport, (
      book.filePath,
      outPath,
    ));
    return (outPath, pageCount);
  }

  /// Shared import logic: segment words, save cache, insert into DB.
  Future<Book> _importManifestWithPages(
    MokuroBookManifest manifest,
    List<MokuroPage> rawPages,
  ) async {
    return _inNewImportDir('manga', (cacheDir) async {
      // Segment words using MeCab, off the UI isolate — imports can be large.
      // The worker also encodes the pages_cache.json content, keeping that
      // multi-MB string build off the UI isolate too.
      // Auto-crop bounds are computed lazily the first time the user enables
      // auto-crop for this manga. Import stores segmented OCR only.
      final segmented = await MokuroWordSegmenter.segmentBookInBackground(
        MokuroBook(
          title: manifest.title,
          imageDirPath: manifest.imageDirPath,
          safTreeUri: manifest.safTreeUri,
          safImageDirRelativePath: manifest.safImageDirRelativePath,
          ocrSource: 'mokuro',
          ocrCompleted: true,
          pages: rawPages,
        ),
      );
      final mokuroBook = segmented.book;
      // A null cacheJson means MeCab was unavailable and nothing was
      // segmented; the import must still write a cache, so encode here.
      final cacheJson = segmented.cacheJson ?? jsonEncode(mokuroBook.toJson());

      // Save pages_cache.json and its original-OCR backup. Encode the
      // multi-MB string once and share the bytes between both writes.
      final cacheBytes = utf8.encode(cacheJson);
      final cacheFile = File(p.join(cacheDir.path, mangaPagesCacheFileName));
      await writeBytesAtomic(cacheFile, cacheBytes);
      final originalBackupFile = File(
        p.join(cacheDir.path, originalMokuroOcrBackupFileName),
      );
      await writeBytesAtomic(originalBackupFile, cacheBytes);

      debugPrint(
        '[MangaImport] Cached ${mokuroBook.pages.length} pages '
        'for "${manifest.title}"',
      );

      // Cover = alphabetically first image file (ASCII sort).
      // The mokuro page order doesn't always start with the cover —
      // filenames like _01.jpg or 000.jpg may precede numbered pages.
      String? coverImagePath;
      if (manifest.imageFileNames.isNotEmpty) {
        final sorted = [...manifest.imageFileNames]..sort();
        for (final fileName in sorted) {
          final ext = p.extension(fileName).toLowerCase();
          if (!CbzParser.imageExtensions.contains(ext)) continue;
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
              totalPages: Value(mokuroBook.pages.length),
            ),
          );

      return (await getBookById(bookId))!;
    });
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
    int bookId, {
    required String? language,
    required String? pageProgressionDirection,
    required String? primaryWritingMode,
    required bool? hasVerticalCss,
  }) => (_db.update(_db.books)..where((t) => t.id.equals(bookId))).write(
    BooksCompanion(
      language: Value(language),
      pageProgressionDirection: Value(pageProgressionDirection),
      primaryWritingMode: Value(primaryWritingMode),
      hasVerticalCss: Value(hasVerticalCss),
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
  /// Reads the cached page data, runs
  /// [MokuroWordSegmenter.segmentBookInBackground] to re-segment (it
  /// replaces each block's words wholesale), and writes back the updated
  /// cache.
  Future<void> reprocessMangaOcr(Book book) async {
    if (book.bookType != 'manga') return;

    final cacheFile = File(p.join(book.filePath, mangaPagesCacheFileName));
    if (!await cacheFile.exists()) {
      throw Exception('Pages cache not found. Try re-importing this manga.');
    }

    final content = await cacheFile.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;
    final mokuroBook = MokuroBook.fromJson(json);

    // Re-run segmentation; the worker isolate also encodes the updated
    // cache JSON. Existing contentBounds (if any) are preserved by
    // MokuroPage.copyWith through the segmentation pipeline, and if MeCab
    // is unavailable the book comes back untouched (keeping the current
    // words is strictly better than wiping them).
    final (book: updated, cacheJson: updatedJson) =
        await MokuroWordSegmenter.segmentBookInBackground(mokuroBook);
    if (updatedJson == null) {
      debugPrint(
        '[MangaOCR] MeCab unavailable — cache left untouched '
        'for "${book.title}"',
      );
      return;
    }

    await writeStringAtomic(cacheFile, updatedJson);

    debugPrint(
      '[MangaOCR] Reprocessed ${updated.pages.length} pages '
      'for "${book.title}"',
    );
  }

  Future<void> backupOriginalMokuroOcrIfNeeded(Book book) async {
    if (book.bookType != 'manga') return;

    final cacheFile = File(p.join(book.filePath, mangaPagesCacheFileName));
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

    final cacheFile = File(p.join(book.filePath, mangaPagesCacheFileName));
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

    final cacheFile = File(p.join(book.filePath, mangaPagesCacheFileName));
    if (!await cacheFile.exists()) {
      throw Exception('Pages cache not found. Try re-importing this manga.');
    }

    final content = await cacheFile.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;
    final mokuroBook = MokuroBook.fromJson(json);

    final clearedPages = mokuroBook.pages
        .map((page) => page.copyWith(blocks: const []))
        .toList();

    final updated = mokuroBook.copyWith(
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

    final cacheFile = File(p.join(book.filePath, mangaPagesCacheFileName));
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

    final updated = mokuroBook.copyWith(
      autoCropVersion: MokuroBook.currentAutoCropVersion,
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
      // Manga rows store the import dir itself; EPUB rows store its
      // `content/` subdir. The name guard makes it impossible for a
      // malformed row to resolve to the books root — and deletes the
      // wrapper even when `content/` is already gone (stale installs
      // used to strand it with the full copied .epub inside).
      final dir = Directory(
        book.bookType == 'manga' ? book.filePath : p.dirname(book.filePath),
      );
      if (importDirName.hasMatch(p.basename(dir.path)) && await dir.exists()) {
        await dir.delete(recursive: true);
      }
    }

    // Clean up bookmarks, highlights and collection memberships for this book
    await (_db.delete(
      _db.bookCollections,
    )..where((t) => t.bookId.equals(bookId))).go();
    await (_db.delete(
      _db.bookmarks,
    )..where((t) => t.bookId.equals(bookId))).go();
    await (_db.delete(
      _db.highlights,
    )..where((t) => t.bookId.equals(bookId))).go();

    await (_db.delete(_db.books)..where((t) => t.id.equals(bookId))).go();
  }

  // ──────────────── Orphan sweep ────────────────

  static const _trashDirName = '.trash';
  static const _trashRetention = Duration(days: 14);

  /// Quarantines import directories under `books/` that no book row
  /// references — leftovers of failed or process-killed imports — and
  /// hard-deletes previously quarantined entries after [_trashRetention].
  ///
  /// Deliberately paranoid: it aborts outright whenever the database cannot
  /// be trusted to enumerate every live book (empty table, or any row whose
  /// path yields no `books/<dir>` segment), skips anything younger than
  /// [minAge] (age comes from the timestamp embedded in every import dir
  /// name), and skips dirs registered in [inFlightImportDirNames].
  /// Never throws. Returns the number of directories quarantined.
  Future<int> sweepOrphanImportDirs({
    Duration minAge = const Duration(days: 7),
  }) async {
    try {
      final booksRoot = await _booksRootDir();
      if (!await booksRoot.exists()) return 0;

      // An empty table alongside existing files can mean the database was
      // lost (e.g. a partial restore) while the books survived — never
      // treat that as "everything is an orphan".
      final books = await getAllBooks();
      if (books.isEmpty) return 0;

      final referenced = <String>{};
      for (final book in books) {
        final own = claimedDirNames(book.filePath).toList();
        if (own.isEmpty) {
          // Parsing that can't see a live book can't be trusted to clear
          // anything — abort, and make the permanently dead sweep visible.
          logUsage(
            'library.orphan_cleanup_aborted',
            attrs: {'reason': 'unparseable_file_path'},
          );
          return 0;
        }
        referenced.addAll(own);
        final cover = book.coverImagePath;
        // Covers are best-effort: they may legitimately live outside
        // books/ or be a content:// URI, which yields no segments.
        if (cover != null) referenced.addAll(claimedDirNames(cover));
      }

      final trashDir = Directory(p.join(booksRoot.path, _trashDirName));
      final trashDeleted = await _emptyExpiredTrash(trashDir);

      final now = DateTime.now();
      var quarantined = 0;
      await for (final entity in booksRoot.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final name = p.basename(entity.path);
        final match = importDirName.firstMatch(name);
        if (match == null) continue;
        if (inFlightImportDirNames.contains(name)) continue;
        if (referenced.contains(name)) continue;
        final createdMs = int.tryParse(match.group(1)!);
        if (createdMs == null) continue;
        final created = DateTime.fromMillisecondsSinceEpoch(createdMs);
        // Also skips future timestamps (negative difference).
        if (now.difference(created) < minAge) continue;
        try {
          await trashDir.create(recursive: true);
          await entity.rename(
            p.join(trashDir.path, '${now.millisecondsSinceEpoch}_$name'),
          );
          quarantined++;
        } catch (_) {
          // Best-effort per entry.
        }
      }

      // ponytail: no restore UI — recovery within the retention window is
      // manual (adb / support); add UI only if a detection bug ever fires.
      if (quarantined > 0 || trashDeleted > 0) {
        logUsage(
          'library.orphan_cleanup',
          attrs: {'quarantined': quarantined, 'trash_deleted': trashDeleted},
        );
      }
      return quarantined;
    } catch (e) {
      logFailure('library.orphan_cleanup', e);
      return 0;
    }
  }

  /// Deletes `.trash` entries older than [_trashRetention]. An entry must
  /// be `<ms>_<name>` where `<name>` satisfies [importDirName] — the same
  /// predicate every other deletion decision consults; anything else is
  /// never deleted.
  static Future<int> _emptyExpiredTrash(Directory trashDir) async {
    if (!await trashDir.exists()) return 0;
    final now = DateTime.now();
    var deleted = 0;
    await for (final entity in trashDir.list(followLinks: false)) {
      final name = p.basename(entity.path);
      final sep = name.indexOf('_');
      if (sep <= 0) continue;
      final quarantinedMs = int.tryParse(name.substring(0, sep));
      if (quarantinedMs == null) continue;
      if (!importDirName.hasMatch(name.substring(sep + 1))) continue;
      final quarantinedAt = DateTime.fromMillisecondsSinceEpoch(quarantinedMs);
      if (now.difference(quarantinedAt) < _trashRetention) continue;
      try {
        await entity.delete(recursive: true);
        deleted++;
      } catch (_) {
        // Best-effort per entry.
      }
    }
    return deleted;
  }
}
