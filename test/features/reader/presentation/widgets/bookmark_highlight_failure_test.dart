import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/reader/data/repositories/bookmark_repository.dart';
import 'package:mekuru/features/reader/data/repositories/highlight_repository.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/features/reader/presentation/widgets/bookmarks_sheet.dart';
import 'package:mekuru/features/reader/presentation/widgets/highlights_sheet.dart';
import 'package:mekuru/l10n/generated/app_localizations_ja.dart';
import 'package:mekuru/main.dart' show databaseProvider;
import 'package:sentry_flutter/sentry_flutter.dart' show SentryAttribute;

import '../../../../shared/test_database.dart';
import '../../../../test_app.dart';

Exception _locked() => Exception('SqliteException(5): database is locked');

/// Reads the real rows; every write fails.
class _BookmarkWritesFail extends BookmarkRepository {
  _BookmarkWritesFail(super.db);

  @override
  Future<void> deleteBookmark(int id) async => throw _locked();
}

class _HighlightWritesFail extends HighlightRepository {
  _HighlightWritesFail(super.db);

  @override
  Future<void> deleteHighlight(int id) async => throw _locked();

  @override
  Future<void> updateHighlightNote(int id, String note) async =>
      throw _locked();
}

void main() {
  final ja = AppLocalizationsJa();
  late AppDatabase db;
  late int bookId;
  final logs = <String>[];
  final attributes = <SentryAttribute>[];

  setUp(() {
    db = createTestDatabase();
    logs.clear();
    attributes.clear();
    usageLogSinkOverride = (message, attrs, {required isWarning}) {
      logs.add(message);
      attributes.addAll(attrs.values);
    };
    usageAnalyticsSinkOverride = (_, _) {};
    usageIssueSinkOverride = (_, _) {};
  });

  tearDown(() async {
    usageLogSinkOverride = null;
    usageAnalyticsSinkOverride = null;
    usageIssueSinkOverride = null;
    await db.close();
  });

  Future<void> seed(WidgetTester tester) async {
    await tester.runAsync(() async {
      bookId = await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(
              title: 'Book',
              filePath: '/books/Book',
              dateAdded: Value(DateTime(2026, 1, 1)),
            ),
          );
      await BookmarkRepository(
        db,
      ).addBookmark(bookId: bookId, cfi: 'epubcfi(/6/4)', chapterTitle: '第一章');
      await HighlightRepository(db).addHighlight(
        bookId: bookId,
        cfiRange: 'epubcfi(/6/4,/1:0,/1:3)',
        selectedText: '吾輩は猫である',
      );
    });
  }

  /// A page whose "open" button runs [open], as the reader opens its sheets.
  Future<void> pumpOpener(
    WidgetTester tester,
    void Function(BuildContext context) open, {
    bool failing = false,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          if (failing) ...[
            bookmarkRepositoryProvider.overrideWithValue(
              _BookmarkWritesFail(db),
            ),
            highlightRepositoryProvider.overrideWithValue(
              _HighlightWritesFail(db),
            ),
          ],
        ],
        child: buildLocalizedTestApp(
          locale: const Locale('ja'),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => open(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> swipeAway(WidgetTester tester, String text) async {
    await tester.fling(find.text(text), const Offset(-500, 0), 1500);
    await tester.pumpAndSettle();
  }

  void expectOn<T>(String message) => expect(
    find.descendant(of: find.byType(T), matching: find.text(message)),
    findsOneWidget,
  );

  void expectNoRawError() {
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('database is locked'), findsNothing);
    for (final attribute in attributes) {
      expect('${attribute.value}', isNot(contains('吾輩')));
    }
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  void openBookmarks(BuildContext context, VoidCallback onDeleted) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) =>
            BookmarksSheet(bookId: bookId, onBookmarkDeleted: onDeleted),
      );

  void openHighlights(BuildContext context, void Function(String) onRemove) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) =>
            HighlightsSheet(bookId: bookId, onRemoveHighlight: onRemove),
      );

  group('a bookmark swiped away', () {
    testWidgets('that cannot be deleted says so on the sheet and comes back', (
      tester,
    ) async {
      await seed(tester);
      var deletedCalls = 0;
      await pumpOpener(
        tester,
        (context) => openBookmarks(context, () => deletedCalls++),
        failing: true,
      );

      await swipeAway(tester, '第一章');

      expectNoRawError();
      expectOn<BookmarksSheet>(ja.readerBookmarkDeleteFailed);
      expect(find.text('第一章'), findsOneWidget);
      expect(deletedCalls, 0);
      expect(logs, contains('reader.bookmark_delete_failed'));
      await unmount(tester);
    });

    testWidgets('that is deleted leaves the list', (tester) async {
      await seed(tester);
      var deletedCalls = 0;
      await pumpOpener(
        tester,
        (context) => openBookmarks(context, () => deletedCalls++),
      );

      await swipeAway(tester, '第一章');

      expect(find.text('第一章'), findsNothing);
      expect(find.text(ja.readerBookmarkDeleteFailed), findsNothing);
      expect(deletedCalls, 1);
      expect(
        await tester.runAsync(() => db.select(db.bookmarks).get()),
        isEmpty,
      );
      await unmount(tester);
    });
  });

  group('a highlight', () {
    testWidgets('swiped away that cannot be deleted says so and stays drawn', (
      tester,
    ) async {
      await seed(tester);
      final removed = <String>[];
      await pumpOpener(
        tester,
        (context) => openHighlights(context, removed.add),
        failing: true,
      );

      await swipeAway(tester, '吾輩は猫である');

      expectNoRawError();
      expectOn<HighlightsSheet>(ja.readerHighlightDeleteFailed);
      expect(find.text('吾輩は猫である'), findsOneWidget);
      expect(removed, isEmpty);
      expect(logs, contains('reader.highlight_delete_failed'));
      await unmount(tester);
    });

    testWidgets('swiped away that is deleted leaves the list and the page', (
      tester,
    ) async {
      await seed(tester);
      final removed = <String>[];
      await pumpOpener(
        tester,
        (context) => openHighlights(context, removed.add),
      );

      await swipeAway(tester, '吾輩は猫である');

      expect(find.text('吾輩は猫である'), findsNothing);
      expect(removed, ['epubcfi(/6/4,/1:0,/1:3)']);
      expect(
        await tester.runAsync(() => db.select(db.highlights).get()),
        isEmpty,
      );
      await unmount(tester);
    });

    testWidgets('deleted from its own sheet that fails says so there and '
        'stays open', (tester) async {
      await seed(tester);
      final removed = <String>[];
      await pumpOpener(
        tester,
        (context) => showModalBottomSheet<void>(
          context: context,
          builder: (_) => HighlightDetailsSheet(
            bookId: bookId,
            cfiRange: 'epubcfi(/6/4,/1:0,/1:3)',
            onRemoveHighlight: removed.add,
          ),
        ),
        failing: true,
      );

      await tester.tap(find.text(ja.commonDelete));
      await tester.pumpAndSettle();

      expectNoRawError();
      expectOn<HighlightDetailsSheet>(ja.readerHighlightDeleteFailed);
      expect(find.byType(HighlightDetailsSheet), findsOneWidget);
      expect(removed, isEmpty);
      await unmount(tester);
    });

    testWidgets('note that cannot be saved says so', (tester) async {
      await seed(tester);
      await pumpOpener(
        tester,
        (context) => showHighlightNoteEditor(context, highlightId: 1),
        failing: true,
      );

      await tester.enterText(find.byType(TextField), 'メモ');
      await tester.tap(find.text(ja.commonSave));
      await tester.pumpAndSettle();

      expectNoRawError();
      expect(find.text(ja.readerNoteSaveFailed), findsOneWidget);
      expect(logs, contains('reader.note_save_failed'));
      for (final attribute in attributes) {
        expect('${attribute.value}', isNot(contains('メモ')));
      }
      await unmount(tester);
    });
  });
}
