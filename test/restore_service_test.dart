import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/backup/data/models/backup_manifest.dart';
import 'package:mekuru/features/backup/data/repositories/pending_book_data_repository.dart';
import 'package:mekuru/features/backup/data/services/backup_serializer.dart';
import 'package:mekuru/features/backup/data/services/book_match_service.dart';
import 'package:mekuru/features/backup/data/services/restore_service.dart';
import 'package:mekuru/features/settings/data/services/app_settings_storage.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

AppDatabase createTestDatabase() => AppDatabase(NativeDatabase.memory());

void main() {
  late AppDatabase db;
  late RestoreService restoreService;
  late PendingBookDataRepository pendingRepo;
  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PreloadedAppSettings.initialThemeMode = ThemeMode.dark;
    PreloadedAppSettings.initialColorThemeName = null;
    db = createTestDatabase();
    pendingRepo = PendingBookDataRepository(db);
    restoreService = RestoreService(db, BookMatchService(), pendingRepo);
    tempDir = await Directory.systemTemp.createTemp('restore_service_test_');
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  BackupManifest buildManifest({
    Map<String, dynamic>? appSettings,
    Map<String, dynamic>? readerSettings,
    List<BackupSavedWordEntry>? savedWords,
    List<BackupBookEntry>? books,
  }) {
    return BackupManifest(
      version: 1,
      createdAt: DateTime.utc(2026, 3, 5),
      settings: BackupSettings(
        app: appSettings ?? {},
        reader: readerSettings ?? {},
      ),
      savedWords: savedWords ?? [],
      books: books ?? [],
    );
  }

  // ── Settings ──

  group('restoreSettings', () {
    test('writes settings to SharedPreferences', () async {
      final manifest = buildManifest(
        appSettings: {'app.theme_mode': 'light', 'app.color_theme': 'blue'},
        readerSettings: {
          'reader.font_size': 24.0,
          'reader.keep_screen_on': true,
        },
      );

      final ok = await restoreService.restoreSettings(manifest);
      expect(ok, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app.theme_mode'), 'light');
      expect(prefs.getString('app.color_theme'), 'blue');
      expect(prefs.getDouble('reader.font_size'), 24.0);
      expect(prefs.getBool('reader.keep_screen_on'), true);
      expect(PreloadedAppSettings.initialThemeMode, ThemeMode.light);
      expect(PreloadedAppSettings.initialColorThemeName, 'blue');
    });
  });

  // ── Saved Words ──

  group('restoreSavedWords', () {
    test('adds new words', () async {
      final manifest = buildManifest(
        savedWords: [
          BackupSavedWordEntry(
            expression: '食べる',
            reading: 'たべる',
            glossaries: jsonEncode(['to eat']),
            sentenceContext: '',
            dateAdded: DateTime.utc(2026, 1, 1),
          ),
          BackupSavedWordEntry(
            expression: '飲む',
            reading: 'のむ',
            glossaries: jsonEncode(['to drink']),
            sentenceContext: '',
            dateAdded: DateTime.utc(2026, 1, 2),
          ),
        ],
      );

      final result = await restoreService.restoreSavedWords(manifest);

      expect(result.added, 2);
      expect(result.skipped, 0);

      final allWords = await db.select(db.savedWords).get();
      expect(allWords, hasLength(2));
    });

    test('skips duplicates by expression+reading', () async {
      // Pre-insert a word
      await db
          .into(db.savedWords)
          .insert(
            SavedWordsCompanion.insert(
              expression: '食べる',
              reading: const Value('たべる'),
              glossaries: '["to eat"]',
            ),
          );

      final manifest = buildManifest(
        savedWords: [
          BackupSavedWordEntry(
            expression: '食べる',
            reading: 'たべる',
            glossaries: jsonEncode(['to eat']),
            sentenceContext: '',
            dateAdded: DateTime.utc(2026, 1, 1),
          ),
          BackupSavedWordEntry(
            expression: '新しい',
            reading: 'あたらしい',
            glossaries: jsonEncode(['new']),
            sentenceContext: '',
            dateAdded: DateTime.utc(2026, 1, 2),
          ),
        ],
      );

      final result = await restoreService.restoreSavedWords(manifest);

      expect(result.added, 1);
      expect(result.skipped, 1);

      final allWords = await db.select(db.savedWords).get();
      expect(allWords, hasLength(2));
    });
  });

  // ── Books ──

  group('restoreBooks', () {
    test('applies data directly when matching book has no user data', () async {
      final bookId = await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(title: 'Test Book', filePath: '/fake/path'),
          );

      final manifest = buildManifest(
        books: [
          BackupBookEntry(
            bookKey: 'epub::test book',
            title: 'Test Book',
            bookType: 'epub',
            readProgress: 0.5,
            lastReadCfi: 'epubcfi(/6/4)',
            bookmarks: [
              BackupBookmarkEntry(
                cfi: 'epubcfi(/6/8)',
                progress: 0.25,
                chapterTitle: 'Ch1',
                userNote: '',
                dateAdded: DateTime.utc(2026, 1, 1),
              ),
            ],
            highlights: [
              BackupHighlightEntry(
                cfiRange: 'epubcfi(/6/4,/1:0,/1:5)',
                selectedText: 'hello',
                color: 'yellow',
                userNote: '',
                dateAdded: DateTime.utc(2026, 1, 1),
              ),
            ],
          ),
        ],
      );

      final result = await restoreService.restoreBooks(manifest);

      expect(result.applied, 1);
      expect(result.pending, 0);
      expect(result.conflicts, isEmpty);

      // Verify book was updated
      final book = await (db.select(
        db.books,
      )..where((t) => t.id.equals(bookId))).getSingle();
      expect(book.readProgress, 0.5);
      expect(book.lastReadCfi, 'epubcfi(/6/4)');

      // Verify bookmark was inserted
      final bookmarks = await (db.select(
        db.bookmarks,
      )..where((t) => t.bookId.equals(bookId))).get();
      expect(bookmarks, hasLength(1));
      expect(bookmarks[0].cfi, 'epubcfi(/6/8)');

      // Verify highlight was inserted
      final highlights = await (db.select(
        db.highlights,
      )..where((t) => t.bookId.equals(bookId))).get();
      expect(highlights, hasLength(1));
      expect(highlights[0].selectedText, 'hello');
    });

    test(
      'returns conflict when matching book has existing user data',
      () async {
        await db
            .into(db.books)
            .insert(
              BooksCompanion.insert(
                title: 'Test Book',
                filePath: '/fake/path',
                readProgress: const Value(0.3),
                lastReadCfi: const Value('epubcfi(/6/2)'),
              ),
            );

        final manifest = buildManifest(
          books: [
            const BackupBookEntry(
              bookKey: 'epub::test book',
              title: 'Test Book',
              bookType: 'epub',
              readProgress: 0.8,
              bookmarks: [],
              highlights: [],
            ),
          ],
        );

        final result = await restoreService.restoreBooks(manifest);

        expect(result.applied, 0);
        expect(result.conflicts, hasLength(1));
        expect(result.conflicts[0].backupEntry.readProgress, 0.8);
        expect(result.conflicts[0].existingBook.readProgress, 0.3);
      },
    );

    test('hash keys match only exact same file content', () async {
      final matchDir = Directory(p.join(tempDir.path, 'match'))..createSync();
      final otherDir = Directory(p.join(tempDir.path, 'other'))..createSync();

      File(p.join(matchDir.path, 'content.txt')).writeAsStringSync('same file');
      File(
        p.join(otherDir.path, 'content.txt'),
      ).writeAsStringSync('different file');

      final matchId = await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(title: 'Same Title', filePath: matchDir.path),
          );
      await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(title: 'Same Title', filePath: otherDir.path),
          );

      final key = await BookMatchService().generateHashKeyForPath(
        matchDir.path,
        'epub',
      );
      expect(key, isNotNull);

      final manifest = buildManifest(
        books: [
          BackupBookEntry(
            bookKey: key!,
            title: 'Same Title',
            bookType: 'epub',
            readProgress: 0.66,
            lastReadCfi: 'epubcfi(/6/12)',
            bookmarks: const [],
            highlights: const [],
          ),
        ],
      );

      final result = await restoreService.restoreBooks(manifest);

      expect(result.applied, 1);
      expect(result.pending, 0);
      expect(result.conflicts, isEmpty);

      final matched = await (db.select(
        db.books,
      )..where((t) => t.id.equals(matchId))).getSingle();
      expect(matched.readProgress, 0.66);
      expect(matched.lastReadCfi, 'epubcfi(/6/12)');
    });

    test('creates pending entry when no matching book exists', () async {
      final manifest = buildManifest(
        books: [
          const BackupBookEntry(
            bookKey: 'epub::missing book',
            title: 'Missing Book',
            bookType: 'epub',
            readProgress: 0.6,
            bookmarks: [],
            highlights: [],
          ),
        ],
      );

      final result = await restoreService.restoreBooks(manifest);

      expect(result.applied, 0);
      expect(result.pending, 1);
      expect(result.conflicts, isEmpty);

      final pending = await pendingRepo.findByBookKey('epub::missing book');
      expect(pending, isNotNull);
    });

    test(
      'restoring unmatched book repeatedly keeps one pending row with latest data',
      () async {
        final firstManifest = buildManifest(
          books: [
            const BackupBookEntry(
              bookKey: 'epub::same title',
              title: 'Same Title',
              bookType: 'epub',
              readProgress: 0.2,
              bookmarks: [],
              highlights: [],
            ),
          ],
        );

        final secondManifest = buildManifest(
          books: [
            const BackupBookEntry(
              bookKey: 'epub::same title',
              title: 'Same Title',
              bookType: 'epub',
              readProgress: 0.9,
              bookmarks: [],
              highlights: [],
            ),
          ],
        );

        await restoreService.restoreBooks(firstManifest);
        await restoreService.restoreBooks(secondManifest);

        final allPending = await pendingRepo.getAll();
        expect(allPending, hasLength(1));

        final decoded = BackupSerializer.decodeBookEntry(
          allPending.single.dataJson,
        );
        expect(decoded.readProgress, 0.9);
      },
    );

    test('applyBookData overwrites existing progress', () async {
      final bookId = await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(
              title: 'Test Book',
              filePath: '/fake/path',
              readProgress: const Value(0.3),
            ),
          );

      const entry = BackupBookEntry(
        bookKey: 'epub::test book',
        title: 'Test Book',
        bookType: 'epub',
        readProgress: 0.9,
        lastReadCfi: 'epubcfi(/6/20)',
        overrideVerticalText: true,
        overrideReadingDirection: 'rtl',
        bookmarks: [],
        highlights: [],
      );

      await restoreService.applyBookData(bookId, entry);

      final book = await (db.select(
        db.books,
      )..where((t) => t.id.equals(bookId))).getSingle();
      expect(book.readProgress, 0.9);
      expect(book.lastReadCfi, 'epubcfi(/6/20)');
      expect(book.overrideVerticalText, true);
      expect(book.overrideReadingDirection, 'rtl');
    });

    test('bookmark dedup skips existing CFIs', () async {
      final bookId = await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(title: 'Test Book', filePath: '/fake/path'),
          );

      // Pre-insert a bookmark
      await db
          .into(db.bookmarks)
          .insert(
            BookmarksCompanion.insert(bookId: bookId, cfi: 'epubcfi(/6/4)'),
          );

      final entry = BackupBookEntry(
        bookKey: 'epub::test book',
        title: 'Test Book',
        bookType: 'epub',
        readProgress: 0.0,
        bookmarks: [
          BackupBookmarkEntry(
            cfi: 'epubcfi(/6/4)', // duplicate
            progress: 0.1,
            chapterTitle: '',
            userNote: '',
            dateAdded: DateTime.utc(2026, 1, 1),
          ),
          BackupBookmarkEntry(
            cfi: 'epubcfi(/6/8)', // new
            progress: 0.2,
            chapterTitle: '',
            userNote: '',
            dateAdded: DateTime.utc(2026, 1, 2),
          ),
        ],
        highlights: [],
      );

      await restoreService.applyBookData(bookId, entry);

      final bookmarks = await (db.select(
        db.bookmarks,
      )..where((t) => t.bookId.equals(bookId))).get();
      expect(bookmarks, hasLength(2)); // 1 existing + 1 new
    });

    test('highlight dedup skips existing cfiRanges', () async {
      final bookId = await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(title: 'Test Book', filePath: '/fake/path'),
          );

      // Pre-insert a highlight
      await db
          .into(db.highlights)
          .insert(
            HighlightsCompanion.insert(
              bookId: bookId,
              cfiRange: 'epubcfi(/6/4,/1:0,/1:5)',
              selectedText: 'existing',
            ),
          );

      final entry = BackupBookEntry(
        bookKey: 'epub::test book',
        title: 'Test Book',
        bookType: 'epub',
        readProgress: 0.0,
        bookmarks: [],
        highlights: [
          BackupHighlightEntry(
            cfiRange: 'epubcfi(/6/4,/1:0,/1:5)', // duplicate
            selectedText: 'existing',
            color: 'yellow',
            userNote: '',
            dateAdded: DateTime.utc(2026, 1, 1),
          ),
          BackupHighlightEntry(
            cfiRange: 'epubcfi(/6/8,/1:0,/1:10)', // new
            selectedText: 'new highlight',
            color: 'blue',
            userNote: '',
            dateAdded: DateTime.utc(2026, 1, 2),
          ),
        ],
      );

      await restoreService.applyBookData(bookId, entry);

      final highlights = await (db.select(
        db.highlights,
      )..where((t) => t.bookId.equals(bookId))).get();
      expect(highlights, hasLength(2)); // 1 existing + 1 new
    });

    test(
      'conflict detection: book with bookmarks but no progress is a conflict',
      () async {
        final bookId = await db
            .into(db.books)
            .insert(
              BooksCompanion.insert(
                title: 'Test Book',
                filePath: '/fake/path',
                // readProgress defaults to 0, lastReadCfi is null
              ),
            );

        // Add a bookmark — this makes the book have user data
        await db
            .into(db.bookmarks)
            .insert(
              BookmarksCompanion.insert(bookId: bookId, cfi: 'epubcfi(/6/4)'),
            );

        final manifest = buildManifest(
          books: [
            const BackupBookEntry(
              bookKey: 'epub::test book',
              title: 'Test Book',
              bookType: 'epub',
              readProgress: 0.5,
              bookmarks: [],
              highlights: [],
            ),
          ],
        );

        final result = await restoreService.restoreBooks(manifest);
        expect(result.conflicts, hasLength(1));
      },
    );
  });
}
