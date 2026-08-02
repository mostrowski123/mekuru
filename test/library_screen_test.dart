import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/library/presentation/providers/library_providers.dart';
import 'package:mekuru/features/library/presentation/screens/library_screen.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_app.dart';

void main() {
  testWidgets('empty library shows quick-start actions', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          booksProvider.overrideWith((ref) => Stream.value(<Book>[])),
        ],
        child: buildLocalizedTestApp(home: const LibraryScreen()),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Import EPUB'), findsOneWidget);
    expect(find.text('Import Manga'), findsOneWidget);
    expect(find.text('Get Dictionaries'), findsOneWidget);
    expect(find.text('Restore Backup'), findsOneWidget);
  });

  testWidgets('import manga opens the type picker with Mokuro guidance', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          booksProvider.overrideWith((ref) => Stream.value(<Book>[])),
        ],
        child: buildLocalizedTestApp(home: const LibraryScreen()),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

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

  testWidgets('completed OCR uses Delete OCR as the primary action title', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: Builder(
          builder: (context) => Text(
            mangaOcrPrimaryActionTitle(
              l10n: context.l10n,
              isRunning: false,
              isMokuroComplete: false,
              hasCompleteOcr: true,
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('Delete OCR'), findsOneWidget);
    expect(find.text('Run OCR'), findsNothing);
  });
}
