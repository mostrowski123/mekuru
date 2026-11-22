import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/library/data/repositories/collection_repository.dart';
import 'package:mekuru/features/library/presentation/providers/library_providers.dart';
import 'package:mekuru/features/library/presentation/screens/library_screen.dart';
import 'package:mekuru/l10n/generated/app_localizations_ja.dart';
import 'package:mekuru/main.dart' show databaseProvider;
import 'package:sentry_flutter/sentry_flutter.dart' show SentryAttribute;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/test_database.dart';
import '../../../test_app.dart';

/// A delete that fails the way a locked database does.
class _DeleteFails extends BookRepository {
  _DeleteFails(super.db);

  @override
  Future<void> deleteBook(int bookId) async =>
      throw Exception('SqliteException(5): database is locked');
}

void main() {
  final ja = AppLocalizationsJa();
  late AppDatabase db;
  final logs = <(String, Map<String, SentryAttribute>)>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = createTestDatabase();
    logs.clear();
    usageLogSinkOverride = (message, attributes, {required isWarning}) =>
        logs.add((message, attributes));
    usageAnalyticsSinkOverride = (_, _) {};
    usageIssueSinkOverride = (_, _) {};
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
                // No import dir: the real delete only removes the rows.
                filePath: '/books/$title',
                dateAdded: Value(DateTime(2026, 1, 1)),
              ),
            ),
      ))!;

  Future<void> pumpLibrary(WidgetTester tester, BookRepository repo) async {
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
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  }

  /// Long-press, Delete in the sheet, Delete in the dialog.
  Future<void> deleteFromSheet(WidgetTester tester, int bookId) async {
    await tester.longPress(find.byKey(ValueKey('book-tile-$bookId')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(ja.libraryDeleteBookTitle));
    await tester.tap(find.text(ja.libraryDeleteBookTitle));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ja.commonDelete));
    await settle(tester);
  }

  void expectNoRawError() {
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('database is locked'), findsNothing);
    expect(
      find.textContaining(ja.commonErrorWithDetails(details: '')),
      findsNothing,
    );
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('a delete that fails says the book is still there, in the '
      "user's language, and keeps the book", (tester) async {
    final id = await insertBook(tester, '吾輩は猫である');
    await pumpLibrary(tester, _DeleteFails(db));

    await deleteFromSheet(tester, id);

    expectNoRawError();
    expect(find.text(ja.libraryDeleteBookFailed), findsOneWidget);
    expect(find.byKey(ValueKey('book-tile-$id')), findsOneWidget);
    expect(logs.map((log) => log.$1), contains('library.book_delete_failed'));
    for (final (_, attributes) in logs) {
      for (final attribute in attributes.values) {
        expect('${attribute.value}', isNot(contains('吾輩')));
      }
    }
    await unmount(tester);
  });

  testWidgets('a delete that fails inside a collection says so there', (
    tester,
  ) async {
    final id = await insertBook(tester, '吾輩は猫である');
    await tester.runAsync(() async {
      final collections = CollectionRepository(db);
      final shelf = await collections.createCollection('棚');
      await collections.addBooksToCollection(shelf, {id});
    });
    await pumpLibrary(tester, _DeleteFails(db));
    await tester.tap(find.text('棚'));
    await tester.pumpAndSettle();

    await deleteFromSheet(tester, id);

    // On the collection's page, not behind it on the library's.
    expectNoRawError();
    expect(find.text(ja.libraryDeleteBookFailed), findsOneWidget);
    expect(find.byKey(ValueKey('book-tile-$id')), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a delete that works removes the book and says nothing', (
    tester,
  ) async {
    final id = await insertBook(tester, '吾輩は猫である');
    await pumpLibrary(tester, BookRepository(db));

    await deleteFromSheet(tester, id);

    expect(find.byKey(ValueKey('book-tile-$id')), findsNothing);
    expect(find.text(ja.libraryDeleteBookFailed), findsNothing);
    expect(await tester.runAsync(() => db.select(db.books).get()), isEmpty);
    expect(logs.map((log) => log.$1), contains('library.book_deleted'));
    expect(
      logs.map((log) => log.$1),
      isNot(contains('library.book_delete_failed')),
    );
    await unmount(tester);
  });
}
