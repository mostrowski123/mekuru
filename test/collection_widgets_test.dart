import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/library/data/repositories/collection_repository.dart';
import 'package:mekuru/features/library/presentation/screens/library_screen.dart';
import 'package:mekuru/features/library/presentation/widgets/collection_widgets.dart';
import 'package:mekuru/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_app.dart';

void main() {
  late AppDatabase db;
  late CollectionRepository repo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    repo = CollectionRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> insertBook(
    WidgetTester tester,
    String title, {
    DateTime? lastReadAt,
  }) async {
    return (await tester.runAsync(
      () => db
          .into(db.books)
          .insert(
            BooksCompanion.insert(
              title: title,
              filePath: '/books/$title',
              lastReadAt: Value(lastReadAt),
            ),
          ),
    ))!;
  }

  Future<void> pumpWithDb(WidgetTester tester, Widget home) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: buildLocalizedTestApp(home: home),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Unmounts the tree so drift stream subscriptions close, then flushes
  /// their zero-duration close timers — otherwise the binding's
  /// timersPending invariant trips at test end.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('books inside folders are hidden from the root grid', (
    tester,
  ) async {
    final inShelf = await insertBook(tester, '坊っちゃん');
    await insertBook(tester, '吾輩は猫である');
    await tester.runAsync(() async {
      final shelf = await repo.createCollection('Shelf');
      await repo.setBookCollections(inShelf, {shelf});
    });

    await pumpWithDb(tester, const LibraryScreen());

    // The folder tile is present; the member book has no tile of its own.
    expect(find.text('Shelf'), findsOneWidget);
    expect(find.byKey(ValueKey('book-tile-$inShelf')), findsNothing);
    expect(find.text('吾輩は猫である'), findsWidgets);

    await unmount(tester);
  });

  testWidgets('tapping a folder opens its book grid and flies the hero', (
    tester,
  ) async {
    final inShelf = await insertBook(tester, '坊っちゃん');
    await insertBook(tester, '吾輩は猫である');
    final shelfId = await tester.runAsync(() async {
      final shelf = await repo.createCollection('Shelf');
      await repo.setBookCollections(inShelf, {shelf});
      return shelf;
    });

    await pumpWithDb(tester, const LibraryScreen());

    // Both routes must carry the same tag or the flight silently no-ops.
    final heroFinder = find.byWidgetPredicate(
      (w) => w is Hero && w.tag == collectionHeroTag(shelfId!),
    );
    expect(heroFinder, findsOneWidget);

    await tester.tap(find.text('Shelf'));
    await tester.pumpAndSettle();

    // Folder screen: app bar title + thumbnail hero + only the member book.
    expect(find.text('Shelf'), findsOneWidget);
    expect(heroFinder, findsOneWidget);
    expect(find.byKey(ValueKey('book-tile-$inShelf')), findsOneWidget);
    expect(find.text('吾輩は猫である'), findsNothing);

    await unmount(tester);
  });

  testWidgets('continue reading surfaces a book inside a folder', (
    tester,
  ) async {
    final inShelf = await insertBook(
      tester,
      '坊っちゃん',
      lastReadAt: DateTime(2026, 6, 10),
    );
    await insertBook(tester, '吾輩は猫である');
    await tester.runAsync(() async {
      final shelf = await repo.createCollection('Shelf');
      await repo.setBookCollections(inShelf, {shelf});
    });

    await pumpWithDb(tester, const LibraryScreen());

    expect(find.text('Continue reading'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('assign sheet toggles membership and creates collections', (
    tester,
  ) async {
    final bookId = await insertBook(tester, '坊っちゃん');
    final book = await tester.runAsync(() async {
      await repo.createCollection('Shelf');
      return (db.select(
        db.books,
      )..where((t) => t.id.equals(bookId))).getSingle();
    });

    await pumpWithDb(
      tester,
      Scaffold(body: CollectionAssignSheet(book: book!)),
    );

    // Check the existing collection → membership written.
    await tester.tap(find.text('Shelf'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    var memberships = await tester.runAsync(
      () => db.select(db.bookCollections).get(),
    );
    expect(memberships!.single.bookId, bookId);

    // Create a new collection from the sheet → auto-assigned.
    await tester.tap(find.text('New collection'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Novels');
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final collections = await tester.runAsync(
      () => db.select(db.collections).get(),
    );
    expect(collections!.map((c) => c.name).toSet(), {'Shelf', 'Novels'});
    memberships = await tester.runAsync(
      () => db.select(db.bookCollections).get(),
    );
    expect(memberships, hasLength(2));

    // Uncheck removes the membership.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Shelf'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    memberships = await tester.runAsync(
      () => db.select(db.bookCollections).get(),
    );
    final shelfId = collections.firstWhere((c) => c.name == 'Shelf').id;
    expect(memberships!.single.collectionId, isNot(shelfId));

    await unmount(tester);
  });

  testWidgets('manage sheet renames and deletes a collection', (tester) async {
    final collection = await tester.runAsync(() async {
      await repo.createCollection('Shlef');
      return (db.select(db.collections)).getSingle();
    });

    await pumpWithDb(
      tester,
      Scaffold(body: CollectionManageSheet(collection: collection!)),
    );

    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Shelf');
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    var collections = await tester.runAsync(
      () => db.select(db.collections).get(),
    );
    expect(collections!.single.name, 'Shelf');

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    // Confirm dialog.
    expect(find.text('Delete collection?'), findsOneWidget);
    await tester.tap(find.text('Delete').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    collections = await tester.runAsync(() => db.select(db.collections).get());
    expect(collections, isEmpty);

    await unmount(tester);
  });
}
