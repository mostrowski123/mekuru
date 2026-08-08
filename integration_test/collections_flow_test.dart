import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/library/data/repositories/collection_repository.dart';
import 'package:mekuru/features/library/presentation/screens/library_screen.dart';
import 'package:mekuru/features/library/presentation/widgets/collection_widgets.dart';

import 'shared/test_infrastructure.dart';
import 'test_helpers.dart';

/// Integration tests for collections (folders) driven through the real UI:
/// long-press → sheets → folder navigation → selection mode → drag reorder.
///
/// Never pumpAndSettle while book/folder tiles are mounted — _CoverTilt's
/// sensor stream rebuilds at 60fps on device and the frame never settles.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder bookTile(int id) => find.byKey(ValueKey('book-tile-$id'));
  Finder folderTile(int id) => find.byKey(ValueKey('folder-tile-$id'));

  Future<void> openFolder(WidgetTester tester, Finder tile) async {
    await tester.tap(tile);
    await pumpUntilVisible(tester, find.byType(CollectionFolderScreen));
    // 320ms fade route + hero flights.
    await tester.pump(const Duration(milliseconds: 500));
  }

  // Waits until the folder route has actually unmounted: during the pop
  // transition the folder screen's tiles are still in the tree, and root
  // tiles become findable before that, so a fixed pump or a wait on a root
  // tile races the teardown.
  Future<void> closeFolder(WidgetTester tester) async {
    await tester.pageBack();
    await tester.pump();
    await pumpUntilGone(tester, find.byType(CollectionFolderScreen));
  }

  testWidgets(
    'creating a collection from a book long-press files it and opens the folder',
    (tester) async {
      final db = createTestDatabase();
      addTearDown(db.close);
      await seedBooks(db, count: 3);
      final ids = (await db.select(db.books).get()).map((b) => b.id).toList();

      await tester.pumpWidget(
        buildIntegrationTestApp(db: db, home: const LibraryScreen()),
      );
      await pumpUntilVisible(tester, bookTile(ids[0]));

      // Long-press → options sheet → assign sheet → create-and-assign.
      await longPressTile(tester, bookTile(ids[0]));
      await tapSheetItem(tester, 'Add to collection');
      await tapSheetItem(tester, 'New collection');
      expect(find.text('Name'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '文学');
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Barrier tap dismisses the assign sheet; wait until it is actually
      // gone or the folder-tile tap below lands on the barrier instead.
      await tester.tapAt(const Offset(10, 10));
      await pumpUntilGone(tester, find.byType(CollectionAssignSheet));

      // Foldered book leaves the root grid; a folder tile takes its place.
      await pumpUntilVisible(tester, find.text('文学'));
      expect(bookTile(ids[0]), findsNothing);
      expect(bookTile(ids[1]), findsOneWidget);
      expect(bookTile(ids[2]), findsOneWidget);

      final collection = (await db.select(db.collections).get()).single;
      expect(collection.name, '文学');
      // The 文学 label above IS the folder tile's own label, so the keyed
      // tile is already mounted.
      expect(folderTile(collection.id), findsOneWidget);

      // Folder screen shows exactly the assigned book.
      await openFolder(tester, folderTile(collection.id));
      expect(bookTile(ids[0]), findsOneWidget);
      expect(bookTile(ids[1]), findsNothing);
      expect(find.text('文学'), findsOneWidget); // app bar title

      await closeFolder(tester);
      expect(folderTile(collection.id), findsOneWidget);
    },
  );

  testWidgets(
    'multi-remove returns books to the library and deleting the folder pops it',
    (tester) async {
      final db = createTestDatabase();
      addTearDown(db.close);
      await seedBooks(db, count: 3);
      final ids = (await db.select(db.books).get()).map((b) => b.id).toList();
      final repo = CollectionRepository(db);
      final cid = await repo.createCollection('文学');
      await repo.addBooksToCollection(cid, ids.toSet());

      await tester.pumpWidget(
        buildIntegrationTestApp(db: db, home: const LibraryScreen()),
      );
      await pumpUntilVisible(tester, folderTile(cid));
      expect(bookTile(ids[0]), findsNothing);

      await openFolder(tester, folderTile(cid));
      expect(bookTile(ids[0]), findsOneWidget);
      expect(bookTile(ids[1]), findsOneWidget);
      expect(bookTile(ids[2]), findsOneWidget);

      // Select two books; removal must confirm only because 2+ are selected.
      await tester.tap(find.byIcon(Icons.checklist));
      await tester.pump();
      expect(find.text('0 selected'), findsOneWidget);
      await tester.tap(bookTile(ids[0]));
      await tester.pump();
      await tester.tap(bookTile(ids[1]));
      await tester.pump();
      expect(find.text('2 selected'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.playlist_remove));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Remove 2 books from this folder?'), findsOneWidget);
      expect(find.text('The books stay in your library.'), findsOneWidget);
      await tester.tap(find.text('Remove'));
      await pumpUntilGone(tester, bookTile(ids[0]));
      expect(bookTile(ids[2]), findsOneWidget);

      // Removed books reappear at root; the survivor stays foldered.
      await closeFolder(tester);
      await pumpUntilVisible(tester, bookTile(ids[0]));
      expect(bookTile(ids[1]), findsOneWidget);
      expect(bookTile(ids[2]), findsNothing);
      expect(folderTile(cid), findsOneWidget);

      // Delete the collection from inside the open folder screen.
      await openFolder(tester, folderTile(cid));
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Delete'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Delete collection?'), findsOneWidget);
      // The manage sheet behind the dialog also has a Delete row; scope to
      // the dialog's confirm button.
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Delete'),
        ),
      );

      // The folder screen auto-pops once its collection is gone.
      await pumpUntilGone(
        tester,
        find.byType(CollectionFolderScreen),
        timeout: const Duration(seconds: 10),
      );
      await pumpUntilVisible(tester, bookTile(ids[2]));
      expect(bookTile(ids[0]), findsOneWidget);
      expect(bookTile(ids[1]), findsOneWidget);
      expect(folderTile(cid), findsNothing);
      expect(find.text('文学'), findsNothing);
    },
  );

  testWidgets(
    'long-press drag in selection mode reorders books and persists positions',
    (tester) async {
      final db = createTestDatabase();
      addTearDown(db.close);
      // Keep the folder at <=4 books: past _FolderPreview.previewCount the
      // book-tile ValueKey moves onto a _StaggeredEntrance wrapper and the
      // dx() geometry below would measure the animating wrapper instead.
      await seedBooks(db, count: 3);
      final ids = (await db.select(db.books).get()).map((b) => b.id).toList();
      final repo = CollectionRepository(db);
      final cid = await repo.createCollection('文学');
      await repo.addBooksToCollection(cid, ids.toSet()); // positions 0,1,2

      await tester.pumpWidget(
        buildIntegrationTestApp(db: db, home: const LibraryScreen()),
      );
      await pumpUntilVisible(tester, folderTile(cid));
      await openFolder(tester, folderTile(cid));

      double dx(int id) => tester.getCenter(bookTile(id)).dx;
      // 3-column grid, one row: insert order left → right.
      expect(dx(ids[0]) < dx(ids[1]), isTrue);
      expect(dx(ids[1]) < dx(ids[2]), isTrue);

      // Drag only works in selection mode (enableDraggable gate).
      await tester.tap(find.byIcon(Icons.checklist));
      await tester.pump();

      // Long-press lift, then walk the first tile onto the last slot.
      final from = tester.getCenter(bookTile(ids[0]));
      final to = tester.getCenter(bookTile(ids[2]));
      final gesture = await tester.startGesture(from);
      await tester.pump(const Duration(milliseconds: 700));
      const steps = 10;
      for (var i = 0; i < steps; i++) {
        await gesture.moveBy((to - from) / steps.toDouble());
        await tester.pump(const Duration(milliseconds: 30));
      }
      // Hover so the package registers the position change before release.
      await tester.pump(const Duration(milliseconds: 400));
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Optimistic UI order flips immediately.
      expect(dx(ids[1]) < dx(ids[2]), isTrue);
      expect(dx(ids[2]) < dx(ids[0]), isTrue);

      // reorderCollectionBooks is fired without await; poll for the write.
      final wantOrder = [ids[1], ids[2], ids[0]];
      List<BookCollection> ordered = const [];
      for (var i = 0; i < 50; i++) {
        ordered =
            (await db.select(db.bookCollections).get())
                .where((r) => r.collectionId == cid)
                .toList()
              ..sort((a, b) => a.position.compareTo(b.position));
        if (listEquals(ordered.map((r) => r.bookId).toList(), wantOrder)) {
          break;
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(ordered.map((r) => r.bookId).toList(), wantOrder);
      // Dense rewrite contract: positions are 0..n-1 after a reorder.
      expect(ordered.map((r) => r.position).toList(), [0, 1, 2]);

      // Leaving selection mode and the folder keeps the new order intact.
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      await closeFolder(tester);
      expect(folderTile(cid), findsOneWidget);
    },
  );
}
