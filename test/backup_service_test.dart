import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/backup/data/services/backup_service.dart';
import 'package:mekuru/features/backup/data/services/book_match_service.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

AppDatabase createTestDatabase() => AppDatabase(NativeDatabase.memory());

void main() {
  late AppDatabase db;
  late BackupService backupService;
  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = createTestDatabase();
    backupService = BackupService(db, BookMatchService());
    tempDir = await Directory.systemTemp.createTemp('backup_service_test_');
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('BackupService.createBackup', () {
    test('creates backup from empty database', () async {
      final manifest = await backupService.createBackup();

      expect(manifest.version, 1);
      expect(manifest.savedWords, isEmpty);
      expect(manifest.books, isEmpty);
      expect(
        manifest.createdAt.isBefore(
          DateTime.now().add(const Duration(seconds: 1)),
        ),
        isTrue,
      );
    });

    test('includes SharedPreferences settings', () async {
      SharedPreferences.setMockInitialValues({
        'app.theme_mode': 'dark',
        'app.color_theme': 'mekuruRed',
        'reader.font_size': 22.0,
        'reader.keep_screen_on': true,
      });

      final manifest = await backupService.createBackup();

      expect(manifest.settings.app['app.theme_mode'], 'dark');
      expect(manifest.settings.app['app.color_theme'], 'mekuruRed');
      expect(manifest.settings.reader['reader.font_size'], 22.0);
      expect(manifest.settings.reader['reader.keep_screen_on'], true);
    });

    test('includes saved words', () async {
      await db
          .into(db.savedWords)
          .insert(
            SavedWordsCompanion.insert(
              expression: '食べる',
              reading: const Value('たべる'),
              glossaries: '["to eat"]',
              sentenceContext: const Value('昨日ケーキを食べた。'),
            ),
          );
      await db
          .into(db.savedWords)
          .insert(
            SavedWordsCompanion.insert(
              expression: '飲む',
              reading: const Value('のむ'),
              glossaries: '["to drink"]',
            ),
          );

      final manifest = await backupService.createBackup();

      expect(manifest.savedWords, hasLength(2));
      expect(manifest.savedWords[0].expression, '食べる');
      expect(manifest.savedWords[0].reading, 'たべる');
      expect(manifest.savedWords[1].expression, '飲む');
    });

    test('includes books with correct bookKey format', () async {
      await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(
              title: 'My EPUB Book',
              filePath: '/fake/path',
            ),
          );

      final manifest = await backupService.createBackup();

      expect(manifest.books, hasLength(1));
      expect(manifest.books[0].bookKey, 'epub::my epub book');
      expect(manifest.books[0].title, 'My EPUB Book');
      expect(manifest.books[0].bookType, 'epub');
    });

    test('prefers sha256 key when book file path exists', () async {
      final dir = Directory(p.join(tempDir.path, 'book_hash'))..createSync();
      File(p.join(dir.path, 'content.txt')).writeAsStringSync('hash me');

      await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(title: 'Hash Book', filePath: dir.path),
          );

      final manifest = await backupService.createBackup();
      final key = manifest.books.single.bookKey;

      expect(key, startsWith('epub::sha256::'));
    });

    test('includes bookmarks and highlights for each book', () async {
      final bookId = await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(title: 'Test Book', filePath: '/fake/path'),
          );

      await db
          .into(db.bookmarks)
          .insert(
            BookmarksCompanion.insert(
              bookId: bookId,
              cfi: 'epubcfi(/6/4)',
              progress: const Value(0.25),
              chapterTitle: const Value('Chapter 1'),
              userNote: const Value('my note'),
            ),
          );

      await db
          .into(db.highlights)
          .insert(
            HighlightsCompanion.insert(
              bookId: bookId,
              cfiRange: 'epubcfi(/6/4,/1:0,/1:10)',
              selectedText: 'highlighted text',
              color: const Value('yellow'),
            ),
          );

      final manifest = await backupService.createBackup();
      final book = manifest.books[0];

      expect(book.bookmarks, hasLength(1));
      expect(book.bookmarks[0].cfi, 'epubcfi(/6/4)');
      expect(book.bookmarks[0].progress, 0.25);
      expect(book.bookmarks[0].chapterTitle, 'Chapter 1');
      expect(book.bookmarks[0].userNote, 'my note');

      expect(book.highlights, hasLength(1));
      expect(book.highlights[0].selectedText, 'highlighted text');
      expect(book.highlights[0].cfiRange, 'epubcfi(/6/4,/1:0,/1:10)');
    });

    test(
      'bookmarks/highlights from different books are correctly associated',
      () async {
        final bookId1 = await db
            .into(db.books)
            .insert(
              BooksCompanion.insert(title: 'Book One', filePath: '/path/1'),
            );
        final bookId2 = await db
            .into(db.books)
            .insert(
              BooksCompanion.insert(title: 'Book Two', filePath: '/path/2'),
            );

        await db
            .into(db.bookmarks)
            .insert(
              BookmarksCompanion.insert(bookId: bookId1, cfi: 'cfi-book1'),
            );
        await db
            .into(db.bookmarks)
            .insert(
              BookmarksCompanion.insert(bookId: bookId2, cfi: 'cfi-book2'),
            );

        final manifest = await backupService.createBackup();

        expect(manifest.books, hasLength(2));

        final b1 = manifest.books.firstWhere((b) => b.title == 'Book One');
        final b2 = manifest.books.firstWhere((b) => b.title == 'Book Two');

        expect(b1.bookmarks, hasLength(1));
        expect(b1.bookmarks[0].cfi, 'cfi-book1');
        expect(b2.bookmarks, hasLength(1));
        expect(b2.bookmarks[0].cfi, 'cfi-book2');
      },
    );

    test('includes per-book settings (overrides, reading progress)', () async {
      await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(
              title: 'Configured Book',
              filePath: '/fake/path',
              language: const Value('ja'),
              readProgress: const Value(0.67),
              lastReadCfi: const Value('epubcfi(/6/10)'),
              overrideVerticalText: const Value(true),
              overrideReadingDirection: const Value('rtl'),
              primaryWritingMode: const Value('vertical-rl'),
              pageProgressionDirection: const Value('rtl'),
            ),
          );

      final manifest = await backupService.createBackup();
      final book = manifest.books[0];

      expect(book.language, 'ja');
      expect(book.readProgress, 0.67);
      expect(book.lastReadCfi, 'epubcfi(/6/10)');
      expect(book.overrideVerticalText, true);
      expect(book.overrideReadingDirection, 'rtl');
      expect(book.primaryWritingMode, 'vertical-rl');
      expect(book.pageProgressionDirection, 'rtl');
    });
  });
}
