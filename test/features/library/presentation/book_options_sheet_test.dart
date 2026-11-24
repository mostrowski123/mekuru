import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/library/presentation/screens/library_screen.dart';
import 'package:mekuru/l10n/generated/app_localizations_ja.dart';
import 'package:mekuru/main.dart' show databaseProvider;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/test_database.dart';
import '../../../test_app.dart';

/// A book's options sheet stays up while the library changes under it, as
/// when an import finishes while it is open (MEKURU-33).
void main() {
  final ja = AppLocalizationsJa();
  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = createTestDatabase();
    usageLogSinkOverride = (_, _, {required isWarning}) {};
    usageAnalyticsSinkOverride = (_, _) {};
    usageIssueSinkOverride = (_, _) {};
  });

  tearDown(() async {
    usageLogSinkOverride = null;
    usageAnalyticsSinkOverride = null;
    usageIssueSinkOverride = null;
    await db.close();
  });

  BooksCompanion row(String title, {DateTime? added, String type = 'epub'}) =>
      BooksCompanion.insert(
        title: title,
        // No folder: the sheet's OCR check finds no page cache.
        filePath: '/books/$title',
        bookType: Value(type),
        dateAdded: Value(added ?? DateTime(2026, 1, 1)),
      );

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Puts [title] in the library and opens its options sheet.
  Future<int> openSheet(
    WidgetTester tester,
    String title, {
    String? type,
  }) async {
    final id = (await tester.runAsync(
      () => db.into(db.books).insert(row(title, type: type ?? 'epub')),
    ))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: buildLocalizedTestApp(
          locale: const Locale('ja'),
          home: const LibraryScreen(),
        ),
      ),
    );
    await settle(tester);
    await tester.longPress(find.byKey(ValueKey('book-tile-$id')));
    await tester.pumpAndSettle();
    return id;
  }

  /// Imports [count] newer books, which the library sorts ahead.
  Future<void> importNewer(WidgetTester tester, int count) async {
    await tester.runAsync(
      () => db.batch(
        (batch) => batch.insertAll(db.books, [
          for (var i = 0; i < count; i++)
            row('新刊$i', added: DateTime(2026, 2, 1, i)),
        ]),
      ),
    );
    await settle(tester);
  }

  Future<void> expectRenameOpens(WidgetTester tester) async {
    await tester.ensureVisible(find.text(ja.commonRename));
    await tester.tap(find.text(ja.commonRename));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text(ja.libraryRenameBookTitle), findsOneWidget);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets("a manga's sheet still draws when its tile is gone", (
    tester,
  ) async {
    final manga = await openSheet(tester, 'よつばと', type: 'manga');

    // No real time passes, so the sheet's OCR check is still reading files.
    await (db.delete(db.books)..where((b) => b.id.equals(manga))).go();
    await settle(tester);
    expect(find.byKey(ValueKey('book-tile-$manga')), findsNothing);
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }

    expect(tester.takeException(), isNull);
    expect(find.text(ja.localOcrRecognize), findsOneWidget);
    await unmount(tester);
  });

  testWidgets("the sheet's actions still work after a new book arrived", (
    tester,
  ) async {
    await openSheet(tester, '吾輩は猫である');
    await importNewer(tester, 1);

    await expectRenameOpens(tester);
    await unmount(tester);
  });

  testWidgets("the sheet's actions still work after imports pushed its "
      'book out of view', (tester) async {
    final book = await openSheet(tester, '吾輩は猫である');
    await importNewer(tester, 60);
    expect(find.byKey(ValueKey('book-tile-$book')), findsNothing);

    await expectRenameOpens(tester);
    await unmount(tester);
  });
}
