import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/app.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/backup/presentation/providers/backup_providers.dart';
import 'package:mekuru/features/library/presentation/screens/library_screen.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/presentation/providers/manga_reader_providers.dart';
import 'package:mekuru/features/manga/presentation/providers/ocr_progress_provider.dart';
import 'package:mekuru/features/manga/presentation/providers/pro_access_provider.dart';
import 'package:mekuru/features/manga/presentation/screens/manga_reader_screen.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/data/services/reader_settings_storage.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/features/reader/presentation/screens/reader_screen.dart';
import 'package:mekuru/main.dart' show databaseProvider, navigatorKey;
import 'package:mekuru/shared/utils/app_routes.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

import 'reader_settings_test_helpers.dart';
import 'test_database.dart';

/// Keeps both readers loading, so the EPUB one never builds its WebView.
class _NeverLoadedReaderSettings implements ReaderSettingsStorage {
  @override
  Future<ReaderSettings?> load() => Completer<ReaderSettings?>().future;

  @override
  Future<void> save(ReaderSettings settings) async {}
}

class _NoWakelock extends WakelockPlusPlatformInterface {
  @override
  bool get isMock => true;

  @override
  Future<bool> get enabled async => false;

  @override
  Future<void> toggle({required bool enable}) async {}
}

/// `tester.restartAndRestore()` stands in for the system killing Mekuru in
/// the background: the tree goes, and comes back from the restoration data
/// the engine kept. The database (the file on disk) survives.
void main() {
  late AppDatabase db;
  late WakelockPlusPlatformInterface originalWakelock;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = createTestDatabase();
    originalWakelock = WakelockPlusPlatformInterface.instance;
    WakelockPlusPlatformInterface.instance = _NoWakelock();
  });

  tearDown(() async {
    WakelockPlusPlatformInterface.instance = originalWakelock;
    await db.close();
  });

  Future<Book> addBook(
    WidgetTester tester, {
    String type = 'epub',
    DateTime? lastReadAt,
  }) async {
    return (await tester.runAsync(() async {
      final id = await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(
              title: 'Book',
              filePath: '/unused',
              bookType: Value(type),
              lastReadAt: Value(lastReadAt),
            ),
          );
      return (db.select(db.books)..where((b) => b.id.equals(id))).getSingle();
    }))!;
  }

  Future<void> pumpApp(WidgetTester tester, Book book) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          readerSettingsStorageProvider.overrideWithValue(
            _NeverLoadedReaderSettings(),
          ),
          readerBrightnessProvider.overrideWith(
            FakeReaderBrightnessNotifier.new,
          ),
          proUnlockedProvider.overrideWith(
            () => FakeProUnlockedNotifier(false),
          ),
          autoBackupCheckerProvider.overrideWith((ref) async {}),
          mangaPagesProvider(
            book.id,
          ).overrideWith((ref) => Completer<MokuroBook>().future),
          ocrProgressProvider(
            book.id,
          ).overrideWith((ref) => Stream.value(null)),
        ],
        child: const MekuruApp(),
      ),
    );
    await settle(tester);
  }

  Future<void> open(WidgetTester tester, Book book) async {
    openBookReader(navigatorKey.currentState!, book);
    await settle(tester);
  }

  Future<void> restartAndRestore(WidgetTester tester) async {
    await tester.restartAndRestore();
    await settle(tester);
  }

  /// Unmounts the tree so drift stream subscriptions close, then flushes
  /// their zero-duration close timers.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  Finder readers() => find.byWidgetPredicate(
    (w) => w is ReaderScreen || w is MangaReaderScreen,
    skipOffstage: false,
  );

  testWidgets('an EPUB reader comes back on the same book', (tester) async {
    final book = await addBook(tester);
    await pumpApp(tester, book);
    openBookReader(navigatorKey.currentState!, book);
    await tester.pump();
    // A live open has the book already: no frame waits for a query.
    expect(tester.widget<ReaderScreen>(readers()).book.id, book.id);
    await settle(tester);

    await restartAndRestore(tester);

    expect(tester.widget<ReaderScreen>(readers()).book.id, book.id);
    await unmount(tester);
  });

  testWidgets('a manga reader comes back on the same book', (tester) async {
    final book = await addBook(tester, type: 'manga');
    await pumpApp(tester, book);
    await open(tester, book);

    await restartAndRestore(tester);

    expect(tester.widget<MangaReaderScreen>(readers()).book.id, book.id);
    await unmount(tester);
  });

  testWidgets('a book deleted meanwhile returns to the library', (
    tester,
  ) async {
    final book = await addBook(tester);
    await pumpApp(tester, book);
    await open(tester, book);
    await tester.runAsync(
      () => (db.delete(db.books)..where((b) => b.id.equals(book.id))).go(),
    );

    await restartAndRestore(tester);

    expect(readers(), findsNothing);
    expect(find.byType(LibraryScreen), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('the last-read startup screen leaves a restored reader alone', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'app.startup_screen': 'lastRead'});
    final book = await addBook(tester, lastReadAt: DateTime(2026, 10, 8));
    await pumpApp(tester, book);
    expect(readers(), findsOneWidget, reason: 'opened at launch');

    await restartAndRestore(tester);
    expect(readers(), findsOneWidget);

    // The library sits offstage under the reader until now, so this is
    // where a late startup action would open the book a second time.
    navigatorKey.currentState!.pop();
    await settle(tester);
    expect(readers(), findsNothing);
    await unmount(tester);
  });

  testWidgets('a remount without restoration data starts on the library', (
    tester,
  ) async {
    final book = await addBook(tester);
    await pumpApp(tester, book);
    await open(tester, book);

    // What iOS does to apply a full restore: the old tree goes, and the app
    // mounts again in the same process.
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpApp(tester, book);

    expect(readers(), findsNothing);
    expect(find.byType(LibraryScreen), findsOneWidget);
    await unmount(tester);
  });
}

/// Lets queries, route transitions and launch actions finish. Not
/// pumpAndSettle: the readers' loading spinners never stop.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}
