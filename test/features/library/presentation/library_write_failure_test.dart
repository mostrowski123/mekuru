import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_reorderable_grid_view/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/library/data/repositories/collection_repository.dart';
import 'package:mekuru/features/library/presentation/providers/library_providers.dart';
import 'package:mekuru/features/library/presentation/screens/library_screen.dart';
import 'package:mekuru/features/library/presentation/widgets/collection_widgets.dart';
import 'package:mekuru/main.dart' show databaseProvider;
import 'package:sentry_flutter/sentry_flutter.dart' show SentryAttribute;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/test_database.dart';
import '../../../test_app.dart';

/// How SQLite reports a full disk: the statement and its parameters, here
/// the new name, follow on a second line.
Exception _diskFull(String parameters) => Exception(
  'SqliteException(13): database or disk is full\n'
  '  Causing statement: UPDATE ..., parameters: $parameters',
);

/// The book writes the library's sheets make all fail. Reads still work, so
/// the screen shows what is stored.
class _BookWritesFail extends BookRepository {
  _BookWritesFail(super.db);

  @override
  Future<void> setFavorite(int bookId, bool favorite) async =>
      throw _diskFull('$favorite, $bookId');

  @override
  Future<void> updateTitle(int bookId, String title) async =>
      throw _diskFull('$title, $bookId');
}

/// Every write to collections and their books fails.
class _CollectionWritesFail extends CollectionRepository {
  _CollectionWritesFail(super.db);

  @override
  Future<int> createCollection(String name) async => throw _diskFull(name);

  @override
  Future<void> renameCollection(int id, String name) async =>
      throw _diskFull('$name, $id');

  @override
  Future<void> setFavorite(int id, bool favorite) async =>
      throw _diskFull('$favorite, $id');

  @override
  Future<void> deleteCollection(int id) async => throw _diskFull('$id');

  @override
  Future<void> setBookCollections(int bookId, Set<int> collectionIds) async =>
      throw _diskFull('$bookId');

  @override
  Future<void> addBooksToCollection(int collectionId, Set<int> bookIds) async =>
      throw _diskFull('$collectionId');

  @override
  Future<void> removeBooksFromCollection(
    int collectionId,
    Set<int> bookIds,
  ) async => throw _diskFull('$collectionId');

  @override
  Future<void> reorderCollectionBooks(
    int collectionId,
    List<int> orderedBookIds,
  ) async => throw _diskFull('$collectionId');
}

const _favoriteFailed = "Couldn't change your favorites. Try again.";
const _collectionChangeFailed =
    "Couldn't save the change to your collections. Try again.";
const _createFailed = "Couldn't create the collection. Try again.";

void main() {
  late AppDatabase db;
  final logs = <(String, Map<String, SentryAttribute>)>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = createTestDatabase();
    logs.clear();
    usageLogSinkOverride = (message, attributes, {required isWarning}) =>
        logs.add((message, attributes));
    usageAnalyticsSinkOverride = (_, _) {};
    usageIssueSinkOverride = (error, _) => fail('issue filed for $error');
  });

  tearDown(() async {
    usageLogSinkOverride = null;
    usageAnalyticsSinkOverride = null;
    usageIssueSinkOverride = null;
    await db.close();
  });

  Future<int> insertBook(WidgetTester tester, String title) async =>
      (await tester.runAsync(
        () => db
            .into(db.books)
            .insert(
              BooksCompanion.insert(
                title: title,
                filePath: '/books/$title',
                dateAdded: Value(DateTime(2026, 1, 1)),
              ),
            ),
      ))!;

  /// A collection holding [books], written past the failing repository.
  Future<int> insertCollection(
    WidgetTester tester,
    String name, {
    Set<int> books = const {},
  }) async => (await tester.runAsync(() async {
    final repo = CollectionRepository(db);
    final id = await repo.createCollection(name);
    for (final book in books) {
      await repo.addBooksToCollection(id, {book});
    }
    return id;
  }))!;

  Future<void> pumpLibrary(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          bookRepositoryProvider.overrideWithValue(_BookWritesFail(db)),
          collectionRepositoryProvider.overrideWithValue(
            _CollectionWritesFail(db),
          ),
        ],
        child: buildLocalizedTestApp(home: const LibraryScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  }

  /// Unmounts the tree so drift's streams close before the database does.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> openBookSheet(WidgetTester tester, int bookId) async {
    await tester.longPress(find.byKey(ValueKey('book-tile-$bookId')));
    await tester.pumpAndSettle();
  }

  Future<void> tapInSheet(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.tap(find.text(text));
    await settle(tester);
  }

  Future<void> enterName(
    WidgetTester tester,
    String name,
    String button,
  ) async {
    await tester.enterText(find.byType(TextField), name);
    await tester.tap(find.text(button));
    await settle(tester);
  }

  /// [message] shows on the sheet that is still up, not behind it.
  void expectOnSheet(String message) => expect(
    find.descendant(of: find.byType(BottomSheet), matching: find.text(message)),
    findsOneWidget,
  );

  void expectLogged(String event) =>
      expect(logs.map((log) => log.$1), contains(event));

  Future<List<Collection>> storedCollections(WidgetTester tester) async =>
      (await tester.runAsync(() => db.select(db.collections).get()))!;

  Future<List<BookCollection>> storedMemberships(WidgetTester tester) async =>
      (await tester.runAsync(() => db.select(db.bookCollections).get()))!;

  group('a book', () {
    testWidgets('favorite that cannot be saved says so and shows no star', (
      tester,
    ) async {
      final id = await insertBook(tester, 'Book');
      await pumpLibrary(tester);

      await openBookSheet(tester, id);
      await tapInSheet(tester, 'Add to favorites');

      expect(find.text(_favoriteFailed), findsOneWidget);
      expect(find.byIcon(Icons.star), findsNothing);
      expectLogged('library.favorite_change_failed');
      await unmount(tester);
    });

    testWidgets('rename that cannot be saved says so and keeps its title, '
        'and telemetry never sees the new title', (tester) async {
      final id = await insertBook(tester, 'Old title');
      await pumpLibrary(tester);

      await openBookSheet(tester, id);
      await tapInSheet(tester, 'Rename');
      await enterName(tester, 'Secret new title', 'Rename');

      expect(find.text("Couldn't rename the book. Try again."), findsOneWidget);
      expect(find.text('Old title'), findsWidgets);
      expect(find.text('Secret new title'), findsNothing);
      expectLogged('library.book_rename_failed');
      for (final (_, attributes) in logs) {
        for (final attribute in attributes.values) {
          expect('${attribute.value}', isNot(contains('Secret')));
        }
      }
      await unmount(tester);
    });
  });

  group('the add-to-collection sheet', () {
    testWidgets('a membership that cannot be saved says so on the sheet and '
        'stays unchecked', (tester) async {
      final id = await insertBook(tester, 'Book');
      await insertCollection(tester, 'Shelf');
      await pumpLibrary(tester);

      await openBookSheet(tester, id);
      await tapInSheet(tester, 'Add to collection');
      await tester.tap(
        find.descendant(
          of: find.byType(CollectionAssignSheet),
          matching: find.text('Shelf'),
        ),
      );
      await settle(tester);

      expectOnSheet(_collectionChangeFailed);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, 'Shelf'),
            )
            .value,
        isFalse,
      );
      expect(await storedMemberships(tester), isEmpty);
      expectLogged('library.collection_change_failed');
      await unmount(tester);
    });

    testWidgets('a new collection that cannot be created says so on the '
        'sheet', (tester) async {
      final id = await insertBook(tester, 'Book');
      await pumpLibrary(tester);

      await openBookSheet(tester, id);
      await tapInSheet(tester, 'Add to collection');
      await tapInSheet(tester, 'New collection');
      await enterName(tester, 'Novels', 'Save');

      expectOnSheet(_createFailed);
      expect(await storedCollections(tester), isEmpty);
      expectLogged('library.collection_create_failed');
      await unmount(tester);
    });
  });

  group('the sheet that adds selected books to collections', () {
    Future<void> openPickSheet(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.checklist));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.select_all));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
      await tester.pumpAndSettle();
    }

    testWidgets('an add that cannot be saved says so and stays open', (
      tester,
    ) async {
      await insertBook(tester, 'Book');
      await insertCollection(tester, 'Shelf');
      await pumpLibrary(tester);

      await openPickSheet(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(CollectionPickSheet),
          matching: find.text('Shelf'),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Add'));
      await settle(tester);

      expectOnSheet(_collectionChangeFailed);
      expect(find.byType(CollectionPickSheet), findsOneWidget);
      expect(await storedMemberships(tester), isEmpty);
      await unmount(tester);
    });

    testWidgets('a new collection that cannot be created says so', (
      tester,
    ) async {
      await insertBook(tester, 'Book');
      await pumpLibrary(tester);

      await openPickSheet(tester);
      await tapInSheet(tester, 'New collection');
      await enterName(tester, 'Novels', 'Save');

      expectOnSheet(_createFailed);
      expect(await storedCollections(tester), isEmpty);
      await unmount(tester);
    });
  });

  group("a collection's sheet", () {
    testWidgets('favorite that cannot be saved says so and shows no star', (
      tester,
    ) async {
      await insertCollection(tester, 'Shelf');
      await pumpLibrary(tester);

      await tester.longPress(find.text('Shelf'));
      await tester.pumpAndSettle();
      await tapInSheet(tester, 'Add to favorites');

      expect(find.text(_favoriteFailed), findsOneWidget);
      expect(find.byIcon(Icons.star), findsNothing);
      await unmount(tester);
    });

    testWidgets('rename that cannot be saved says so and keeps the name', (
      tester,
    ) async {
      await insertCollection(tester, 'Shelf');
      await pumpLibrary(tester);

      await tester.longPress(find.text('Shelf'));
      await tester.pumpAndSettle();
      await tapInSheet(tester, 'Rename');
      await enterName(tester, 'Shelves', 'Save');

      expect(
        find.text("Couldn't rename the collection. Try again."),
        findsOneWidget,
      );
      expect(find.text('Shelf'), findsOneWidget);
      expect(find.text('Shelves'), findsNothing);
      expectLogged('library.collection_rename_failed');
      await unmount(tester);
    });

    testWidgets('delete that fails says so and keeps the collection', (
      tester,
    ) async {
      await insertCollection(tester, 'Shelf');
      await pumpLibrary(tester);

      await tester.longPress(find.text('Shelf'));
      await tester.pumpAndSettle();
      await tapInSheet(tester, 'Delete');
      await tester.tap(find.text('Delete').last);
      await settle(tester);

      expect(
        find.text("Couldn't delete the collection. Try again."),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('folder-tile-1')), findsOneWidget);
      expect(await storedCollections(tester), hasLength(1));
      expectLogged('library.collection_delete_failed');
      await unmount(tester);
    });
  });

  group('an open collection', () {
    Future<List<int>> openShelfOfTwo(WidgetTester tester) async {
      final ids = [
        await insertBook(tester, 'Book 0'),
        await insertBook(tester, 'Book 1'),
      ];
      await insertCollection(tester, 'Shelf', books: ids.toSet());
      await pumpLibrary(tester);
      await tester.tap(find.text('Shelf'));
      await tester.pumpAndSettle();
      return ids;
    }

    double left(WidgetTester tester, int id) =>
        tester.getTopLeft(find.byKey(ValueKey('book-tile-$id'))).dx;

    testWidgets('removing books that fails says so and keeps the selection', (
      tester,
    ) async {
      final ids = await openShelfOfTwo(tester);
      await tester.tap(find.byIcon(Icons.checklist));
      await tester.pump();
      await tester.tap(find.byKey(ValueKey('book-tile-${ids[0]}')));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.playlist_remove));
      await settle(tester);

      expect(find.text(_collectionChangeFailed), findsOneWidget);
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.byKey(ValueKey('book-tile-${ids[0]}')), findsOneWidget);
      expect(await storedMemberships(tester), hasLength(2));
      await unmount(tester);
    });

    testWidgets('an order that cannot be saved says so and goes back', (
      tester,
    ) async {
      final ids = await openShelfOfTwo(tester);
      expect(left(tester, ids[0]), lessThan(left(tester, ids[1])));

      // What a finished drag hands the screen; the drag itself is the
      // grid package's.
      tester
          .widget<ReorderableBuilder<Book>>(
            find.byKey(const Key('folder-reorderable')),
          )
          .onReorder!((books) => books.reversed.toList());
      await settle(tester);

      expect(find.text(_collectionChangeFailed), findsOneWidget);
      expect(left(tester, ids[0]), lessThan(left(tester, ids[1])));
      await unmount(tester);
    });
  });
}
