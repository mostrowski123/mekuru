import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/library/presentation/providers/library_providers.dart';
import 'package:mekuru/features/library/presentation/screens/library_screen.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/l10n/generated/app_localizations_ja.dart';
import 'package:mekuru/main.dart' show databaseProvider;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:workmanager_platform_interface/workmanager_platform_interface.dart';

import '../../shared/test_database.dart';
import '../../test_app.dart';

/// Delete OCR ends in [failure].
class _ClearFails extends BookRepository {
  _ClearFails(super.db, this.failure);

  final Object failure;

  @override
  Future<void> clearMangaOcr(Book book) async => throw failure;
}

/// Delete OCR stops any OCR work queued for the book first.
class _NoWork extends WorkmanagerPlatform {
  @override
  Future<void> cancelByTag(String tag) async {}
}

void main() {
  final ja = AppLocalizationsJa();
  late AppDatabase db;
  late Directory dir;
  final logs = <String>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WorkmanagerPlatform.instance = _NoWork();
    db = createTestDatabase();
    dir = Directory.systemTemp.createTempSync('pages_missing_');
    logs.clear();
    usageLogSinkOverride = (message, _, {required isWarning}) =>
        logs.add(message);
    usageAnalyticsSinkOverride = (_, _) {};
    usageIssueSinkOverride = (_, _) {};
  });

  tearDown(() async {
    usageLogSinkOverride = null;
    usageAnalyticsSinkOverride = null;
    usageIssueSinkOverride = null;
    await db.close();
    dir.deleteSync(recursive: true);
  });

  Future<Book> insertManga() async {
    final id = await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            title: '秘密の漫画',
            filePath: dir.path,
            bookType: const Value('manga'),
            dateAdded: Value(DateTime(2026, 1, 1)),
          ),
        );
    return (db.select(db.books)..where((t) => t.id.equals(id))).getSingle();
  }

  group('a manga whose page data is gone', () {
    final calls = <String, Future<Object?> Function(BookRepository, Book)>{
      'reprocessMangaOcr': (repo, book) => repo.reprocessMangaOcr(book),
      'backupOriginalMokuroOcrIfNeeded': (repo, book) =>
          repo.backupOriginalMokuroOcrIfNeeded(book),
      'restoreOriginalMokuroOcr': (repo, book) =>
          repo.restoreOriginalMokuroOcr(book),
      'clearMangaOcr': (repo, book) => repo.clearMangaOcr(book),
      'ensureMangaAutoCropComputed': (repo, book) =>
          repo.ensureMangaAutoCropComputed(book),
    };
    for (final MapEntry(key: name, value: call) in calls.entries) {
      test('$name says so with MangaPagesUnavailable.pagesMissing', () async {
        final book = await insertManga();
        await expectLater(
          call(BookRepository(db), book),
          throwsA(MangaPagesUnavailable.pagesMissing),
        );
      });
    }
  });

  // The manga reader passes the auto-crop error's text along; the message
  // leaves it out in every language.
  test('the auto-crop failure never shows the error', () {
    const error =
        'Exception: Pages cache not found. Try re-importing this manga.';
    for (final l10n in AppLocalizations.supportedLocales.map(
      lookupAppLocalizations,
    )) {
      expect(
        l10n.mangaAutoCropSetupFailed(details: error),
        isNot(contains('Exception')),
      );
    }
  });

  group('Delete OCR in the library', () {
    /// A manga with OCR text, so its sheet offers Delete OCR.
    Future<int> mangaWithText(WidgetTester tester) async {
      final book = (await tester.runAsync(() async {
        const manga = MokuroBook(
          title: '秘密の漫画',
          imageDirPath: '',
          pages: [
            MokuroPage(
              pageIndex: 0,
              imageFileName: '001.jpg',
              imgWidth: 100,
              imgHeight: 100,
              blocks: [
                MokuroTextBlock(
                  box: [0, 0, 10, 10],
                  vertical: true,
                  fontSize: 10,
                  linesCoords: [],
                  lines: ['吾輩は猫である'],
                ),
              ],
            ),
          ],
        );
        File(
          p.join(dir.path, mangaPagesCacheFileName),
        ).writeAsStringSync(jsonEncode(manga.toJson()));
        return insertManga();
      }))!;
      return book.id;
    }

    /// Lets real file and isolate work finish until [finder] shows.
    Future<void> waitFor(WidgetTester tester, Finder finder) async {
      for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
    }

    Future<void> deleteOcr(
      WidgetTester tester,
      int id,
      BookRepository repo,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            bookRepositoryProvider.overrideWithValue(repo),
          ],
          child: buildLocalizedTestApp(
            locale: const Locale('ja'),
            home: const LibraryScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.longPress(find.byKey(ValueKey('book-tile-$id')));
      // The sheet reads the page data from disk before it offers Delete OCR.
      await waitFor(tester, find.text(ja.ocrRemoveActionTitle));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(ja.ocrRemoveActionTitle));
      await tester.tap(find.text(ja.ocrRemoveActionTitle));
      await tester.pumpAndSettle();
      await tester.tap(find.text(ja.ocrRemoveActionTitle).last);
      await waitFor(tester, find.byType(SnackBar));
      await tester.pumpAndSettle();
    }

    Future<void> unmount(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('that fails says so in Japanese, without the error', (
      tester,
    ) async {
      final id = await mangaWithText(tester);
      await deleteOcr(
        tester,
        id,
        _ClearFails(db, Exception('database is locked: 秘密の漫画')),
      );

      expect(find.textContaining('Exception'), findsNothing);
      expect(find.textContaining('database is locked'), findsNothing);
      expect(find.text(ja.ocrDeleteFailed), findsOneWidget);
      expect(logs, contains('ocr.delete_failed'));
      await unmount(tester);
    });

    testWidgets('whose page data went missing says to import it again', (
      tester,
    ) async {
      final id = await mangaWithText(tester);
      await deleteOcr(
        tester,
        id,
        _ClearFails(db, MangaPagesUnavailable.pagesMissing),
      );

      expect(find.textContaining('MangaPagesUnavailable'), findsNothing);
      expect(find.text(ja.mangaReaderPagesMissing), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('that works says it deleted the OCR', (tester) async {
      final id = await mangaWithText(tester);
      await deleteOcr(tester, id, BookRepository(db));

      expect(find.text(ja.ocrRemovedFromBook), findsOneWidget);
      expect(find.text(ja.ocrDeleteFailed), findsNothing);
      await unmount(tester);
    });
  });
}
