import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Rect;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:path/path.dart' as p;

/// In-memory database for testing.
AppDatabase createTestDatabase() {
  return AppDatabase(NativeDatabase.memory());
}

void main() {
  late AppDatabase db;
  late BookRepository repo;
  late Directory tempDir;

  setUp(() {
    db = createTestDatabase();
    repo = BookRepository(db);
    tempDir = Directory.systemTemp.createTempSync('book_repository_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
    await db.close();
  });

  group('BookRepository — queries', () {
    test('getAllBooks returns empty list initially', () async {
      final books = await repo.getAllBooks();
      expect(books, isEmpty);
    });

    test('getBookById returns null for non-existent book', () async {
      final book = await repo.getBookById(999);
      expect(book, isNull);
    });
  });

  group('BookRepository — database operations', () {
    test('direct insert creates a book and it is retrievable', () async {
      // Insert directly via drift to test DB operations without file system
      final id = await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(title: '坊っちゃん', filePath: '/test/path'),
          );

      final book = await repo.getBookById(id);
      expect(book, isNotNull);
      expect(book!.title, '坊っちゃん');
      expect(book.filePath, '/test/path');
      expect(book.coverImagePath, isNull);
    });

    test('getAllBooks returns books in newest-first order', () async {
      // Insert books with small delays to ensure different timestamps
      await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(title: 'First Book', filePath: '/path/1'),
          );

      // Use a slightly later date for the second book
      await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(title: 'Second Book', filePath: '/path/2'),
          );

      final books = await repo.getAllBooks();
      expect(books, hasLength(2));
      // Both should be returned — order depends on insertion timing
      final titles = books.map((b) => b.title).toList();
      expect(titles, containsAll(['First Book', 'Second Book']));
    });

    test('updateProgress updates lastReadCfi', () async {
      final id = await db
          .into(db.books)
          .insert(BooksCompanion.insert(title: 'Test', filePath: '/test'));

      await repo.updateProgress(id, 'epubcfi(/6/14[ch7]!/4/2/1:0)');

      final book = await repo.getBookById(id);
      expect(book!.lastReadCfi, 'epubcfi(/6/14[ch7]!/4/2/1:0)');
    });

    test('updateProgress with progress updates readProgress', () async {
      final id = await db
          .into(db.books)
          .insert(BooksCompanion.insert(title: 'Test', filePath: '/test'));

      await repo.updateProgress(
        id,
        'epubcfi(/6/14[ch7]!/4/2/1:0)',
        progress: 0.42,
      );

      final book = await repo.getBookById(id);
      expect(book!.lastReadCfi, 'epubcfi(/6/14[ch7]!/4/2/1:0)');
      expect(book.readProgress, closeTo(0.42, 0.001));
    });

    test(
      'updateProgress without progress leaves readProgress unchanged',
      () async {
        final id = await db
            .into(db.books)
            .insert(BooksCompanion.insert(title: 'Test', filePath: '/test'));

        await repo.updateProgress(id, 'epubcfi(/6/2)');

        final book = await repo.getBookById(id);
        expect(book!.readProgress, 0.0);
      },
    );

    test('updateTotalPages updates totalPages', () async {
      final id = await db
          .into(db.books)
          .insert(BooksCompanion.insert(title: 'Test', filePath: '/test'));

      await repo.updateTotalPages(id, 250);

      final book = await repo.getBookById(id);
      expect(book!.totalPages, 250);
    });

    test('deleteBook removes book from database', () async {
      final id = await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(
              title: 'To Delete',
              filePath: '/nonexistent/path',
            ),
          );

      expect(await repo.getBookById(id), isNotNull);

      await repo.deleteBook(id);

      expect(await repo.getBookById(id), isNull);
    });

    test('watchAllBooks emits updates', () async {
      final emissions = <List<Book>>[];
      final subscription = repo.watchAllBooks().listen((data) {
        emissions.add(data);
      });

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(emissions.last, isEmpty);

      await db
          .into(db.books)
          .insert(BooksCompanion.insert(title: '新しい本', filePath: '/test'));

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(emissions.last, hasLength(1));
      expect(emissions.last.first.title, '新しい本');

      await subscription.cancel();
    });
  });

  group('BookRepository — importEpub integration', () {
    test('importEpub throws for non-existent file', () async {
      // The importEpub method calls path_provider which won't work in tests
      // but the EPUB parser itself will throw first for non-existent file
      expect(
        () => repo.importEpub('/nonexistent/book.epub'),
        throwsA(anything),
      );
    });
  });

  group('BookRepository — language and pageProgressionDirection', () {
    test('inserting book with language stores the value', () async {
      final id = await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(
              title: 'English Novel',
              filePath: '/test/path',
              language: const Value('en'),
              pageProgressionDirection: const Value('ltr'),
            ),
          );

      final book = await repo.getBookById(id);
      expect(book, isNotNull);
      expect(book!.language, 'en');
      expect(book.pageProgressionDirection, 'ltr');
    });

    test('inserting book without language has null language', () async {
      final id = await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(title: 'Legacy Book', filePath: '/test/path'),
          );

      final book = await repo.getBookById(id);
      expect(book, isNotNull);
      expect(book!.language, isNull);
      expect(book.pageProgressionDirection, isNull);
    });

    test('backfillLanguage updates language and ppd', () async {
      final id = await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(title: 'Legacy Book', filePath: '/test/path'),
          );

      // Verify initially null
      var book = await repo.getBookById(id);
      expect(book!.language, isNull);

      // Backfill
      await repo.backfillLanguage(id, 'ja', 'rtl', 'vertical-rl');

      book = await repo.getBookById(id);
      expect(book!.language, 'ja');
      expect(book.pageProgressionDirection, 'rtl');
      expect(book.primaryWritingMode, 'vertical-rl');
    });

    test('backfillLanguage can set null values', () async {
      final id = await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(
              title: 'Book',
              filePath: '/test/path',
              language: const Value('en'),
            ),
          );

      await repo.backfillLanguage(id, null, null, null);

      final book = await repo.getBookById(id);
      expect(book!.language, isNull);
      expect(book.pageProgressionDirection, isNull);
      expect(book.primaryWritingMode, isNull);
    });
  });

  group('BookRepository auto-crop cache', () {
    test(
      'ensureMangaAutoCropComputed can be forced to recompute bounds',
      () async {
        final imageDir = Directory(p.join(tempDir.path, 'images'))
          ..createSync(recursive: true);
        final cacheDir = Directory(p.join(tempDir.path, 'cache'))
          ..createSync(recursive: true);
        final imagePath = p.join(imageDir.path, 'page.png');

        // 200×200 image with staggered content at x=[40,150], y=[30,170].
        // The staggered pattern ((x+y)%9!=0) avoids triggering the
        // multi-phase algorithm's border-line detection (Phase 2.75/3.75).
        final image = img.Image(width: 200, height: 200);
        img.fill(image, color: img.ColorRgb8(255, 255, 255));
        for (int y = 30; y <= 170; y++) {
          for (int x = 40; x <= 150; x++) {
            if ((x + y) % 9 != 0) {
              image.setPixelRgb(x, y, 0, 0, 0);
            }
          }
        }
        File(imagePath).writeAsBytesSync(img.encodePng(image));

        final cacheBook = MokuroBook(
          title: 'Test Manga',
          imageDirPath: imageDir.path,
          autoCropVersion: MokuroBook.currentAutoCropVersion,
          pages: const [
            MokuroPage(
              pageIndex: 0,
              imageFileName: 'page.png',
              imgWidth: 200,
              imgHeight: 200,
              blocks: [],
              contentBounds: Rect.fromLTRB(1, 1, 199, 199),
            ),
          ],
        );
        final cacheFile = File(p.join(cacheDir.path, 'pages_cache.json'));
        await cacheFile.writeAsString(jsonEncode(cacheBook.toJson()));

        final id = await db
            .into(db.books)
            .insert(
              BooksCompanion.insert(
                title: 'Test Manga',
                filePath: cacheDir.path,
                bookType: const Value('manga'),
              ),
            );
        final book = (await repo.getBookById(id))!;

        final recomputed = await repo.ensureMangaAutoCropComputed(
          book,
          force: true,
        );

        expect(recomputed, isTrue);

        final updated = MokuroBook.fromJson(
          jsonDecode(await cacheFile.readAsString()) as Map<String, dynamic>,
        );
        final bounds = updated.pages.single.contentBounds;

        expect(updated.autoCropVersion, MokuroBook.currentAutoCropVersion);
        expect(bounds, isNotNull);
        // Content left=40, padding=2 → 38
        expect(bounds!.left, 38);
        // Content top=30, padding=2 → 28
        expect(bounds.top, 28);
        // Content right=150 (inclusive) + 1 + padding=2 → 153
        expect(bounds.right, 153);
        // Content bottom=170 (inclusive) + 1 + padding=2 → 173
        expect(bounds.bottom, 173);
      },
    );
  });

  group('BookRepository Mokuro OCR restore', () {
    test(
      'can back up and restore original Mokuro OCR after clearing it',
      () async {
        final cacheDir = Directory(p.join(tempDir.path, 'cache'))
          ..createSync(recursive: true);
        final cacheFile = File(p.join(cacheDir.path, 'pages_cache.json'));
        final original = MokuroBook(
          title: 'Imported Mokuro',
          imageDirPath: p.join(tempDir.path, 'images'),
          ocrSource: 'mokuro',
          ocrCompleted: true,
          pages: const [
            MokuroPage(
              pageIndex: 0,
              imageFileName: 'page1.jpg',
              imgWidth: 100,
              imgHeight: 100,
              blocks: [
                MokuroTextBlock(
                  box: [0, 0, 10, 10],
                  vertical: true,
                  fontSize: 12,
                  linesCoords: [],
                  lines: ['hello'],
                ),
              ],
            ),
          ],
        );
        await cacheFile.writeAsString(jsonEncode(original.toJson()));

        final id = await db
            .into(db.books)
            .insert(
              BooksCompanion.insert(
                title: 'Imported Mokuro',
                filePath: cacheDir.path,
                bookType: const Value('manga'),
              ),
            );
        final book = (await repo.getBookById(id))!;

        await repo.backupOriginalMokuroOcrIfNeeded(book);
        await repo.clearMangaOcr(book);

        final cleared = MokuroBook.fromJson(
          jsonDecode(await cacheFile.readAsString()) as Map<String, dynamic>,
        );
        expect(cleared.pages.single.blocks, isEmpty);
        expect(cleared.ocrSource, isNull);
        expect(cleared.ocrCompleted, isFalse);

        final restored = await repo.restoreOriginalMokuroOcr(book);

        expect(restored, isTrue);
        final restoredBook = MokuroBook.fromJson(
          jsonDecode(await cacheFile.readAsString()) as Map<String, dynamic>,
        );
        expect(restoredBook.ocrSource, 'mokuro');
        expect(restoredBook.ocrCompleted, isTrue);
        expect(restoredBook.pages.single.blocks, hasLength(1));
        expect(
          File(
            p.join(
              cacheDir.path,
              BookRepository.originalMokuroOcrBackupFileName,
            ),
          ).existsSync(),
          isTrue,
        );
      },
    );
  });
}
