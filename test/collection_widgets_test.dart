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

  testWidgets('tapping a folder opens its book grid', (tester) async {
    final inShelf = await insertBook(tester, '坊っちゃん');
    await insertBook(tester, '吾輩は猫である');
    await tester.runAsync(() async {
      final shelf = await repo.createCollection('Shelf');
      await repo.setBookCollections(inShelf, {shelf});
    });

    await pumpWithDb(tester, const LibraryScreen());

    // Tapping the label opens too — the whole tile is the closed container.
    await tester.tap(find.text('Shelf'));
    await tester.pumpAndSettle();

    // Folder screen: app bar title and only the member book.
    expect(find.text('Shelf'), findsOneWidget);
    expect(find.byKey(ValueKey('book-tile-$inShelf')), findsOneWidget);
    expect(find.text('吾輩は猫である'), findsNothing);

    await unmount(tester);
  });

  testWidgets('a book filed in two folders gets one hero tag per folder', (
    tester,
  ) async {
    // Two heroes sharing a tag in one subtree throws, so the same book on
    // two folder faces must not produce the same tag.
    final bookId = await insertBook(tester, '坊っちゃん');
    final ids = await tester.runAsync(() async {
      final a = await repo.createCollection('A');
      final b = await repo.createCollection('B');
      await repo.setBookCollections(bookId, {a, b});
      return (a, b);
    });

    await pumpWithDb(tester, const LibraryScreen());

    expect(tester.takeException(), isNull);
    final (a, b) = ids!;
    expect(folderCoverHeroTag(a, bookId), isNot(folderCoverHeroTag(b, bookId)));
    for (final tag in [
      folderCoverHeroTag(a, bookId),
      folderCoverHeroTag(b, bookId),
    ]) {
      expect(
        find.byWidgetPredicate((w) => w is Hero && w.tag == tag),
        findsOneWidget,
      );
    }

    await unmount(tester);
  });

  testWidgets('folder screen pairs a hero for each cover the face showed', (
    tester,
  ) async {
    final first = await insertBook(tester, '坊っちゃん');
    final shelfId = await tester.runAsync(() async {
      final shelf = await repo.createCollection('Shelf');
      await repo.setBookCollections(first, {shelf});
      return shelf;
    });

    await pumpWithDb(tester, const LibraryScreen());
    await tester.tap(find.text('Shelf'));
    await tester.pumpAndSettle();

    // Same tag on both routes, or the cover has nothing to fly to.
    expect(
      find.byWidgetPredicate(
        (w) => w is Hero && w.tag == folderCoverHeroTag(shelfId!, first),
      ),
      findsOneWidget,
    );

    await unmount(tester);
  });

  testWidgets('non-hero folder tiles stagger in instead of popping', (
    tester,
  ) async {
    final ids = <int>[];
    for (var i = 0; i < 6; i++) {
      ids.add(await insertBook(tester, 'Book $i'));
    }
    await tester.runAsync(() async {
      final shelf = await repo.createCollection('Shelf');
      await repo.addBooksToCollection(shelf, ids.toSet());
    });

    await pumpWithDb(tester, const LibraryScreen());
    await tester.tap(find.text('Shelf'));

    // Mid-flight (route is 320ms). The page-level route fade dims every
    // tile equally, so the discriminating fact is that two non-hero tiles
    // have DIFFERENT nearest-fade opacities — only a per-tile stagger
    // produces that.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    // The stagger wrapper carries the tile key, so its own fade is the
    // first FadeTransition among the key's descendants.
    double nearestFadeOpacity(int bookId) {
      final fades = find.descendant(
        of: find.byKey(ValueKey('book-tile-$bookId')),
        matching: find.byType(FadeTransition),
      );
      expect(fades, findsWidgets);
      return tester.widget<FadeTransition>(fades.first).opacity.value;
    }

    final fifth = nearestFadeOpacity(ids[4]);
    final sixth = nearestFadeOpacity(ids[5]);
    expect(sixth, lessThan(1.0));
    expect(fifth, isNot(equals(sixth)));

    // Settled: fully visible.
    await tester.pumpAndSettle();
    expect(nearestFadeOpacity(ids[5]), 1.0);

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
