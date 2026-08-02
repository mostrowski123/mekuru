import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/reader/data/models/highlight_color.dart';
import 'package:mekuru/features/reader/data/repositories/bookmark_repository.dart';
import 'package:mekuru/features/reader/data/repositories/highlight_repository.dart';
import 'package:mekuru/features/reader/presentation/widgets/bookmarks_sheet.dart';
import 'package:mekuru/features/reader/presentation/widgets/highlights_sheet.dart';

import 'shared/test_infrastructure.dart';
import 'test_helpers.dart';

Future<int> _insertBook(AppDatabase db, String title) => db
    .into(db.books)
    .insert(BooksCompanion.insert(title: title, filePath: '/fake/$title.epub'));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('BookmarkRepository', () {
    late AppDatabase db;
    late BookmarkRepository repo;

    setUp(() {
      db = createTestDatabase();
      repo = BookmarkRepository(db);
    });
    tearDown(() => db.close());

    test('add → watch → delete lifecycle round-trips through the DB', () async {
      final bookId = await _insertBook(db, 'Test');

      final id = await repo.addBookmark(
        bookId: bookId,
        cfi: 'epubcfi(/6/4)',
        progress: 0.25,
        chapterTitle: 'Chapter 1',
        userNote: 'note',
      );

      // The watch stream is what the reader UI consumes; asserting through
      // it (rather than the one-shot getter) exercises the actual contract.
      final stored = await repo.watchBookmarksForBook(bookId).first;
      expect(stored, hasLength(1));
      expect(stored.single.id, id);
      expect(stored.single.cfi, 'epubcfi(/6/4)');
      expect(stored.single.progress, 0.25);
      expect(stored.single.chapterTitle, 'Chapter 1');
      expect(stored.single.userNote, 'note');

      await repo.deleteBookmark(id);
      expect(await repo.watchBookmarksForBook(bookId).first, isEmpty);
    });

    test('deleteBookmarksForBook clears only the targeted book', () async {
      final book1 = await _insertBook(db, 'Book 1');
      final book2 = await _insertBook(db, 'Book 2');

      await repo.addBookmark(bookId: book1, cfi: 'b1-cfi');
      await repo.addBookmark(bookId: book2, cfi: 'b2-cfi');

      await repo.deleteBookmarksForBook(book1);

      expect(await repo.getBookmarksForBook(book1), isEmpty);
      expect(await repo.getBookmarksForBook(book2), hasLength(1));
    });

    test('getBookmarkAtCfi returns matching row or null', () async {
      final bookId = await _insertBook(db, 'Test');
      await repo.addBookmark(bookId: bookId, cfi: 'epubcfi(/6/4)');

      final hit = await repo.getBookmarkAtCfi(bookId, 'epubcfi(/6/4)');
      expect(hit, isNotNull);
      expect(hit!.cfi, 'epubcfi(/6/4)');

      final miss = await repo.getBookmarkAtCfi(bookId, 'epubcfi(/6/99)');
      expect(miss, isNull);
    });
  });

  group('HighlightRepository', () {
    late AppDatabase db;
    late HighlightRepository repo;

    setUp(() {
      db = createTestDatabase();
      repo = HighlightRepository(db);
    });
    tearDown(() => db.close());

    test('add → watch → delete lifecycle round-trips through the DB', () async {
      final bookId = await _insertBook(db, 'Test');

      final id = await repo.addHighlight(
        bookId: bookId,
        cfiRange: 'epubcfi(/6/4,/1:0,/1:10)',
        selectedText: 'hello world',
        color: HighlightColor.blue.name,
        userNote: 'my note',
      );

      final stored = await repo.watchHighlightsForBook(bookId).first;
      expect(stored, hasLength(1));
      expect(stored.single.id, id);
      expect(stored.single.cfiRange, 'epubcfi(/6/4,/1:0,/1:10)');
      expect(stored.single.selectedText, 'hello world');
      expect(stored.single.color, HighlightColor.blue.name);
      expect(stored.single.userNote, 'my note');

      await repo.deleteHighlight(id);
      expect(await repo.watchHighlightsForBook(bookId).first, isEmpty);
    });

    test('updateHighlightNote and updateHighlightColor persist', () async {
      final bookId = await _insertBook(db, 'Test');
      final id = await repo.addHighlight(
        bookId: bookId,
        cfiRange: 'cfi-range',
        selectedText: 'text',
      );

      await repo.updateHighlightNote(id, 'updated note');
      await repo.updateHighlightColor(id, HighlightColor.pink.name);

      final stored = await repo.getAllHighlightsForBook(bookId);
      expect(stored.single.userNote, 'updated note');
      expect(stored.single.color, HighlightColor.pink.name);
    });

    test('deleteHighlightsForBook clears only the targeted book', () async {
      final book1 = await _insertBook(db, 'Book 1');
      final book2 = await _insertBook(db, 'Book 2');

      await repo.addHighlight(
        bookId: book1,
        cfiRange: 'c1',
        selectedText: 't1',
      );
      await repo.addHighlight(
        bookId: book2,
        cfiRange: 'c2',
        selectedText: 't2',
      );

      await repo.deleteHighlightsForBook(book1);

      expect(await repo.getAllHighlightsForBook(book1), isEmpty);
      expect(await repo.getAllHighlightsForBook(book2), hasLength(1));
    });
  });

  group('BookmarksSheet widget', () {
    testWidgets('renders seeded bookmarks and swipe-to-delete removes them', (
      tester,
    ) async {
      final db = createTestDatabase();
      addTearDown(db.close);

      final bookId = await _insertBook(db, 'Test');
      final repo = BookmarkRepository(db);
      await repo.addBookmark(
        bookId: bookId,
        cfi: 'epubcfi(/6/4)',
        chapterTitle: 'Chapter 1',
      );

      await tester.pumpWidget(
        buildIntegrationTestApp(
          db: db,
          home: Scaffold(
            body: BookmarksSheet(bookId: bookId, onBookmarkDeleted: () {}),
          ),
        ),
      );

      await pumpUntilVisible(tester, find.text('Chapter 1'));

      await tester.fling(find.text('Chapter 1'), const Offset(-500, 0), 1500);
      await tester.pumpAndSettle();

      expect(find.text('Chapter 1'), findsNothing);
      expect(await repo.getBookmarksForBook(bookId), isEmpty);
    });
  });

  group('HighlightsSheet widget', () {
    testWidgets('renders seeded highlights and swipe-to-delete removes them', (
      tester,
    ) async {
      final db = createTestDatabase();
      addTearDown(db.close);

      final bookId = await _insertBook(db, 'Test');
      final repo = HighlightRepository(db);
      await repo.addHighlight(
        bookId: bookId,
        cfiRange: 'epubcfi(/6/4,/1:0,/1:10)',
        selectedText: 'highlighted passage',
      );

      await tester.pumpWidget(
        buildIntegrationTestApp(
          db: db,
          home: Scaffold(
            body: HighlightsSheet(bookId: bookId, onRemoveHighlight: (_) {}),
          ),
        ),
      );

      await pumpUntilVisible(tester, find.text('highlighted passage'));

      await tester.fling(
        find.text('highlighted passage'),
        const Offset(-500, 0),
        1500,
      );
      await tester.pumpAndSettle();

      expect(find.text('highlighted passage'), findsNothing);
      expect(await repo.getAllHighlightsForBook(bookId), isEmpty);
    });
  });
}
