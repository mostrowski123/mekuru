import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/free_books/data/models/aozora_work.dart';
import 'package:mekuru/features/free_books/data/models/tadoku_book.dart';
import 'package:mekuru/features/free_books/presentation/providers/free_books_providers.dart';
import 'package:mekuru/features/free_books/presentation/screens/free_books_screen.dart';
import 'package:mekuru/features/library/presentation/providers/library_providers.dart';
import 'package:mekuru/features/library/presentation/screens/library_screen.dart';
import 'package:mekuru/features/settings/presentation/screens/downloads_screen.dart';
import 'package:mekuru/features/stats/presentation/providers/stats_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shared/fake_download_notifiers.dart';
import 'test_app.dart';

Future<void> pumpEmptyLibrary(
  WidgetTester tester, {
  List<Override> overrides = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        booksProvider.overrideWith((ref) => Stream.value(<Book>[])),
        ...overrides,
      ],
      child: buildLocalizedTestApp(home: const LibraryScreen()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('empty library shows quick-start actions', (tester) async {
    await pumpEmptyLibrary(tester);

    expect(find.text('Import EPUB'), findsOneWidget);
    expect(find.text('Import Manga'), findsOneWidget);
    expect(find.text('Get Dictionaries'), findsOneWidget);
    expect(find.text('Restore Backup'), findsOneWidget);
    expect(find.text('Browse free books'), findsOneWidget);
  });

  testWidgets('Browse free books opens the in-app Free books screen', (
    tester,
  ) async {
    await pumpEmptyLibrary(
      tester,
      overrides: [
        aozoraCatalogProvider.overrideWith((ref) async => <AozoraWork>[]),
        tadokuCatalogProvider.overrideWith((ref) async => <TadokuBook>[]),
        sessionsProvider.overrideWith((ref) => Stream.value(const [])),
      ],
    );

    await tester.ensureVisible(find.text('Browse free books'));
    await tester.tap(find.text('Browse free books'));
    await tester.pumpAndSettle();

    expect(find.byType(FreeBooksScreen), findsOneWidget);
  });

  testWidgets('Get Dictionaries starts the starter pack and opens Downloads', (
    tester,
  ) async {
    mockWifiConnected(true);
    final started = <String>[];
    await pumpEmptyLibrary(
      tester,
      overrides: fakeDownloadNotifierOverrides(started),
    );

    await tester.tap(find.text('Get Dictionaries'));
    await tester.pumpAndSettle();

    expect(started, unorderedEquals(<String>['catalog:jitendex', 'jpdb']));
    expect(find.byType(DownloadsScreen), findsOneWidget);
  });

  testWidgets('import manga opens the type picker with Mokuro guidance', (
    tester,
  ) async {
    await pumpEmptyLibrary(tester);

    await tester.tap(find.text('Import Manga'));
    await tester.pumpAndSettle();

    expect(find.text('Mokuro folder'), findsOneWidget);
    expect(find.text('CBZ archive'), findsOneWidget);
    expect(
      find.text(
        'Select the folder that contains a .mokuro or .html file alongside the images folder.',
      ),
      findsOneWidget,
    );
    expect(find.text('What is Mokuro?'), findsOneWidget);
  });

  // MEKURU-1Y: file_picker's iOS folder picker stays in folder mode after a
  // cancel, so every later file pick in the session returns a bare path and
  // crashes. The folder is picked through our own bridge instead.
  testWidgets('mokuro folder import picks through mekuru/ios_files', (
    tester,
  ) async {
    const iosFiles = MethodChannel('mekuru/ios_files');
    final bridgeCalls = <String>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(iosFiles, (call) async {
      bridgeCalls.add(call.method);
      return null; // cancelled
    });
    addTearDown(() => messenger.setMockMethodCallHandler(iosFiles, null));
    await pumpEmptyLibrary(tester);

    await tester.tap(find.text('Import Manga'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mokuro folder'));
    await tester.pumpAndSettle();

    expect(bridgeCalls, ['pickFolder']);
  });

  group('mostRecentlyReadBook', () {
    Book makeBook(int id, {DateTime? lastReadAt}) => Book(
      id: id,
      title: 'Book $id',
      filePath: '/books/$id',
      bookType: 'epub',
      totalPages: 0,
      readProgress: 0.0,
      dateAdded: DateTime(2026, 1, 1),
      lastReadAt: lastReadAt,
    );

    test('returns null for an empty list', () {
      expect(mostRecentlyReadBook([]), isNull);
    });

    test('returns null when no book has been read', () {
      expect(mostRecentlyReadBook([makeBook(1), makeBook(2)]), isNull);
    });

    test('returns the book with the latest lastReadAt', () {
      final books = [
        makeBook(1, lastReadAt: DateTime(2026, 6, 1)),
        makeBook(2, lastReadAt: DateTime(2026, 6, 10)),
        makeBook(3),
      ];
      expect(mostRecentlyReadBook(books)!.id, 2);
    });
  });

  group('continue-reading card', () {
    Book makeBook(
      int id,
      String title, {
      DateTime? lastReadAt,
      double readProgress = 0.0,
    }) => Book(
      id: id,
      title: title,
      filePath: '/books/$id',
      bookType: 'epub',
      totalPages: 0,
      readProgress: readProgress,
      dateAdded: DateTime(2026, 1, 1),
      lastReadAt: lastReadAt,
    );

    Future<void> pumpLibrary(WidgetTester tester, List<Book> books) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        ProviderScope(
          overrides: [booksProvider.overrideWith((ref) => Stream.value(books))],
          child: buildLocalizedTestApp(home: const LibraryScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('shows the most recently read book with progress', (
      tester,
    ) async {
      await pumpLibrary(tester, [
        makeBook(1, '坊っちゃん', lastReadAt: DateTime(2026, 6, 1)),
        makeBook(
          2,
          '吾輩は猫である',
          lastReadAt: DateTime(2026, 6, 10),
          readProgress: 0.42,
        ),
      ]);

      expect(find.text('Continue reading'), findsOneWidget);
      expect(find.text('42%'), findsOneWidget);
      // The card shows the title once; the grid tile shows it again.
      expect(find.text('吾輩は猫である'), findsWidgets);
    });

    testWidgets('is hidden when no book has been read yet', (tester) async {
      await pumpLibrary(tester, [makeBook(1, '坊っちゃん'), makeBook(2, '走れメロス')]);

      expect(find.text('Continue reading'), findsNothing);
    });
  });
}
