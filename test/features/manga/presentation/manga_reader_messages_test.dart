import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/presentation/providers/ocr_progress_provider.dart';
import 'package:mekuru/features/manga/presentation/providers/pro_access_provider.dart';
import 'package:mekuru/features/manga/presentation/screens/manga_reader_screen.dart';
import 'package:mekuru/features/manga/presentation/widgets/manga_page_view.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

import '../../../shared/reader_settings_test_helpers.dart';
import '../../../shared/test_database.dart';
import '../../../test_app.dart';

class _NoWakelock extends WakelockPlusPlatformInterface {
  @override
  bool get isMock => true;

  @override
  Future<bool> get enabled async => false;

  @override
  Future<void> toggle({required bool enable}) async {}
}

const _japanese = Locale('ja');
const _couldNotLoad = 'マンガを読み込めませんでした';

void main() {
  testWidgets('a page whose image cannot load says so in the app language', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildLocalizedTestApp(
        locale: _japanese,
        home: const Scaffold(
          body: MangaPageView(
            pageIndex: 0,
            page: MokuroPage(
              pageIndex: 0,
              imageFileName: 'p1.jpg',
              imgWidth: 100,
              imgHeight: 150,
              blocks: [],
            ),
            imageDirPath: 'Z:/does-not-exist',
          ),
        ),
      ),
    );
    // The file read is real IO.
    for (
      var i = 0;
      i < 10 && find.byIcon(Icons.broken_image).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    expect(find.text('このページの画像を読み込めませんでした。'), findsOneWidget);
    expect(find.text('Could not load image'), findsNothing);
  });

  group('a manga the reader cannot open says why in the app language', () {
    late WakelockPlusPlatformInterface originalWakelock;
    setUp(() {
      originalWakelock = WakelockPlusPlatformInterface.instance;
      WakelockPlusPlatformInterface.instance = _NoWakelock();
      SharedPreferences.setMockInitialValues({});
    });
    tearDown(() => WakelockPlusPlatformInterface.instance = originalWakelock);

    /// Opens a manga stored in [dir], whose row is in the library only when
    /// [inLibrary].
    Future<void> openReader(
      WidgetTester tester, {
      required String dir,
      required bool inLibrary,
    }) async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final row = BooksCompanion.insert(
        title: 'Manga',
        filePath: dir,
        bookType: const Value('manga'),
      );
      final id = inLibrary
          ? (await tester.runAsync(() => db.into(db.books).insert(row)))!
          : 1;
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          ocrProgressProvider(id).overrideWith((ref) => Stream.value(null)),
          readerBrightnessProvider.overrideWith(
            FakeReaderBrightnessNotifier.new,
          ),
          proUnlockedProvider.overrideWith(() => FakeProUnlockedNotifier(true)),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: buildLocalizedTestApp(
            locale: _japanese,
            home: MangaReaderScreen(
              book: Book(
                id: id,
                isFavorite: false,
                title: 'Manga',
                filePath: dir,
                bookType: 'manga',
                totalPages: 1,
                readProgress: 0,
                dateAdded: DateTime(2026, 10, 7),
              ),
            ),
          ),
        ),
      );
      // The database read and the file check are real IO.
      for (
        var i = 0;
        i < 20 && find.text(_couldNotLoad).evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(find.text(_couldNotLoad), findsOneWidget);
    }

    testWidgets('its page data is missing', (tester) async {
      final dir = Directory.systemTemp.createTempSync('manga_no_cache_');
      addTearDown(() => dir.deleteSync(recursive: true));

      await openReader(tester, dir: dir.path, inLibrary: true);

      expect(
        find.text('このマンガのページデータが見つかりません。マンガをもう一度インポートしてください。'),
        findsOneWidget,
      );
    });

    testWidgets('it is no longer in the library', (tester) async {
      await openReader(tester, dir: '/unused', inLibrary: false);

      expect(find.text('この本はもう端末にありません'), findsOneWidget);
    });
  });
}
