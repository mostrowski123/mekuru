import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/backup/data/repositories/pending_book_data_repository.dart';
import 'package:mekuru/features/backup/data/services/backup_serializer.dart';
import 'package:mekuru/features/backup/data/services/backup_service.dart';
import 'package:mekuru/features/backup/data/services/book_match_service.dart';
import 'package:mekuru/features/backup/data/services/restore_service.dart';
import 'package:mekuru/features/settings/data/services/app_settings_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shared/test_infrastructure.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'backup → encode → decode → restore preserves settings, words, books, bookmarks, highlights',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'app.theme_mode': 'dark',
        'app.color_theme': 'mekuruBlue',
        'app.startup_screen': 'library',
        'app.library_sort_order': 'dateAdded',
        'reader.font_size': 22.0,
        'reader.keep_screen_on': true,
      });

      final sourceDb = createTestDatabase();
      addTearDown(sourceDb.close);

      // Commas, quotes, and Japanese punctuation in context exercise JSON
      // escaping in the encoded backup.
      await sourceDb
          .into(sourceDb.savedWords)
          .insert(
            SavedWordsCompanion.insert(
              expression: '食べる',
              reading: const Value('たべる'),
              glossaries: jsonEncode(['to eat', 'to consume']),
              sentenceContext: const Value('彼は、毎日「ご飯」を食べる。'),
              dateAdded: Value(DateTime.utc(2026, 4, 1, 9)),
            ),
          );
      await sourceDb
          .into(sourceDb.savedWords)
          .insert(
            SavedWordsCompanion.insert(
              expression: '走る',
              reading: const Value('はしる'),
              glossaries: jsonEncode(['to run', 'to dash']),
              dateAdded: Value(DateTime.utc(2026, 4, 2, 10)),
            ),
          );

      // One book with rich per-book settings + bookmarks + highlights,
      // one plain to ensure minimal books also round-trip.
      final melosId = await sourceDb
          .into(sourceDb.books)
          .insert(
            BooksCompanion.insert(
              title: '走れメロス',
              filePath: '/fake/melos.epub',
              language: const Value('ja'),
              readProgress: const Value(0.42),
              lastReadCfi: const Value('epubcfi(/6/4!/4/2/2)'),
              lastReadAt: Value(DateTime.utc(2026, 5, 10, 14, 30)),
              overrideVerticalText: const Value(true),
              overrideReadingDirection: const Value('rtl'),
              primaryWritingMode: const Value('vertical-rl'),
              pageProgressionDirection: const Value('rtl'),
            ),
          );
      await sourceDb
          .into(sourceDb.books)
          .insert(
            BooksCompanion.insert(
              title: 'こころ',
              filePath: '/fake/kokoro.epub',
              language: const Value('ja'),
            ),
          );

      await sourceDb
          .into(sourceDb.bookmarks)
          .insert(
            BookmarksCompanion.insert(
              bookId: melosId,
              cfi: 'epubcfi(/6/4!/4)',
              progress: const Value(0.10),
              chapterTitle: const Value('第一章'),
              userNote: const Value('面白い'),
              dateAdded: Value(DateTime.utc(2026, 5, 1, 8)),
            ),
          );
      await sourceDb
          .into(sourceDb.bookmarks)
          .insert(
            BookmarksCompanion.insert(
              bookId: melosId,
              cfi: 'epubcfi(/6/8!/4)',
              dateAdded: Value(DateTime.utc(2026, 5, 2, 8)),
            ),
          );
      await sourceDb
          .into(sourceDb.highlights)
          .insert(
            HighlightsCompanion.insert(
              bookId: melosId,
              cfiRange: 'epubcfi(/6/4,/1:0,/1:10)',
              selectedText: 'メロスは激怒した',
              color: const Value('yellow'),
              userNote: const Value('印象的'),
              dateAdded: Value(DateTime.utc(2026, 5, 3, 8)),
            ),
          );

      // The JSON encode/decode hop catches serializer asymmetries that
      // unit-level encode-only or decode-only tests can miss.
      final manifest1 = await BackupService(
        sourceDb,
        BookMatchService(),
      ).createBackup();
      final json = BackupSerializer.encode(manifest1);
      final manifest2 = BackupSerializer.decode(json);

      SharedPreferences.setMockInitialValues({});
      PreloadedAppSettings.initialThemeMode = ThemeMode.light;
      PreloadedAppSettings.initialColorThemeName = null;

      final targetDb = createTestDatabase();
      addTearDown(targetDb.close);

      await targetDb
          .into(targetDb.books)
          .insert(
            BooksCompanion.insert(title: '走れメロス', filePath: '/fake/melos.epub'),
          );
      await targetDb
          .into(targetDb.books)
          .insert(
            BooksCompanion.insert(title: 'こころ', filePath: '/fake/kokoro.epub'),
          );

      final restoreService = RestoreService(
        targetDb,
        BookMatchService(),
        PendingBookDataRepository(targetDb),
      );

      expect(await restoreService.restoreSettings(manifest2), isTrue);
      final wordResult = await restoreService.restoreSavedWords(manifest2);
      expect(wordResult.added, 2);
      expect(wordResult.skipped, 0);
      final bookResult = await restoreService.restoreBooks(manifest2);
      expect(bookResult.applied, 2);
      expect(bookResult.pending, 0);
      expect(bookResult.conflicts, isEmpty);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app.theme_mode'), 'dark');
      expect(prefs.getString('app.color_theme'), 'mekuruBlue');
      expect(prefs.getString('app.startup_screen'), 'library');
      expect(prefs.getString('app.library_sort_order'), 'dateAdded');
      expect(prefs.getDouble('reader.font_size'), 22.0);
      expect(prefs.getBool('reader.keep_screen_on'), true);
      expect(PreloadedAppSettings.initialThemeMode, ThemeMode.dark);
      expect(PreloadedAppSettings.initialColorThemeName, 'mekuruBlue');

      final restoredWords = await targetDb.select(targetDb.savedWords).get();
      expect(restoredWords, hasLength(2));
      final taberu = restoredWords.firstWhere((w) => w.expression == '食べる');
      expect(taberu.reading, 'たべる');
      expect(taberu.glossaries, jsonEncode(['to eat', 'to consume']));
      expect(taberu.sentenceContext, '彼は、毎日「ご飯」を食べる。');
      // Drift returns DateTimes in local time; compare as instants.
      expect(taberu.dateAdded.toUtc(), DateTime.utc(2026, 4, 1, 9));

      final melosBook = await (targetDb.select(
        targetDb.books,
      )..where((t) => t.title.equals('走れメロス'))).getSingle();
      expect(melosBook.readProgress, 0.42);
      expect(melosBook.lastReadCfi, 'epubcfi(/6/4!/4/2/2)');
      expect(melosBook.lastReadAt?.toUtc(), DateTime.utc(2026, 5, 10, 14, 30));
      expect(melosBook.overrideVerticalText, true);
      expect(melosBook.overrideReadingDirection, 'rtl');

      final bookmarks = await (targetDb.select(
        targetDb.bookmarks,
      )..where((t) => t.bookId.equals(melosBook.id))).get();
      expect(bookmarks, hasLength(2));
      final bm1 = bookmarks.firstWhere((b) => b.cfi == 'epubcfi(/6/4!/4)');
      expect(bm1.progress, 0.10);
      expect(bm1.chapterTitle, '第一章');
      expect(bm1.userNote, '面白い');
      expect(bm1.dateAdded.toUtc(), DateTime.utc(2026, 5, 1, 8));

      final highlights = await (targetDb.select(
        targetDb.highlights,
      )..where((t) => t.bookId.equals(melosBook.id))).get();
      expect(highlights, hasLength(1));
      expect(highlights[0].cfiRange, 'epubcfi(/6/4,/1:0,/1:10)');
      expect(highlights[0].selectedText, 'メロスは激怒した');
      expect(highlights[0].color, 'yellow');
      expect(highlights[0].userNote, '印象的');
      expect(highlights[0].dateAdded.toUtc(), DateTime.utc(2026, 5, 3, 8));
    },
  );

  testWidgets(
    're-applying the same backup is safe: words dedupe, books conflict cleanly',
    (tester) async {
      // Catches regressions where restore is invoked twice (e.g. user
      // re-imports the same file). We should never double-insert saved words
      // or silently overwrite book data.
      SharedPreferences.setMockInitialValues({});

      final sourceDb = createTestDatabase();
      addTearDown(sourceDb.close);

      await sourceDb
          .into(sourceDb.savedWords)
          .insert(
            SavedWordsCompanion.insert(
              expression: '読む',
              reading: const Value('よむ'),
              glossaries: jsonEncode(['to read']),
            ),
          );
      final bookId = await sourceDb
          .into(sourceDb.books)
          .insert(
            BooksCompanion.insert(
              title: 'Test Book',
              filePath: '/fake/test.epub',
              readProgress: const Value(0.5),
            ),
          );
      await sourceDb
          .into(sourceDb.bookmarks)
          .insert(
            BookmarksCompanion.insert(bookId: bookId, cfi: 'epubcfi(/6/4)'),
          );

      final manifest = await BackupService(
        sourceDb,
        BookMatchService(),
      ).createBackup();

      // Target has the matching book imported but no user data, so the first
      // restore can apply cleanly without triggering a conflict.
      final targetDb = createTestDatabase();
      addTearDown(targetDb.close);
      await targetDb
          .into(targetDb.books)
          .insert(
            BooksCompanion.insert(
              title: 'Test Book',
              filePath: '/fake/test.epub',
            ),
          );

      final restoreService = RestoreService(
        targetDb,
        BookMatchService(),
        PendingBookDataRepository(targetDb),
      );

      expect((await restoreService.restoreSavedWords(manifest)).added, 1);
      expect((await restoreService.restoreBooks(manifest)).applied, 1);

      // After the first restore the book has user data, so re-applying must
      // surface a conflict rather than silently overwriting.
      final words2 = await restoreService.restoreSavedWords(manifest);
      expect(words2.added, 0);
      expect(words2.skipped, 1);

      final books2 = await restoreService.restoreBooks(manifest);
      expect(books2.applied, 0);
      expect(books2.conflicts, hasLength(1));

      expect(await targetDb.select(targetDb.savedWords).get(), hasLength(1));
      expect(await targetDb.select(targetDb.bookmarks).get(), hasLength(1));
    },
  );
}
