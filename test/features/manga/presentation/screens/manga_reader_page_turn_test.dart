// Taps and swipes turn manga pages. With Animations on the pages slide, as
// in 1.74.5; with it off the next page is shown in the next frame, so
// e-reader displays never draw a page half way across.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/library/presentation/providers/library_providers.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/presentation/providers/manga_reader_providers.dart';
import 'package:mekuru/features/manga/presentation/providers/ocr_progress_provider.dart';
import 'package:mekuru/features/manga/presentation/providers/pro_access_provider.dart';
import 'package:mekuru/features/manga/presentation/screens/manga_reader_screen.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/features/reader/presentation/widgets/reader_page_navigation.dart';
import 'package:mekuru/l10n/generated/app_localizations_en.dart';
import 'package:mekuru/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

import '../../../../shared/reader_settings_test_helpers.dart';
import '../../../../shared/test_database.dart';
import '../../../../test_app.dart';

class _NoWakelock extends WakelockPlusPlatformInterface {
  @override
  bool get isMock => true;

  @override
  Future<bool> get enabled async => false;

  @override
  Future<void> toggle({required bool enable}) async {}
}

/// Keeps the reader's saves out of the test database.
class _NoProgress extends BookRepository {
  _NoProgress(super.db);

  @override
  Future<void> updateProgress(
    int bookId,
    String cfi, {
    double? progress,
    String? href,
    double? hrefProgression,
  }) async {}
}

const _pageCount = 4;
final _en = AppLocalizationsEn();

final _book = Book(
  id: 1,
  isFavorite: false,
  title: 'Manga',
  filePath: '/unused',
  bookType: 'manga',
  totalPages: _pageCount,
  readProgress: 0,
  dateAdded: DateTime(2026, 11, 18),
);

/// Opens the book in single-page view, read right to left.
Future<void> _openReader(
  WidgetTester tester, {
  required bool animations,
}) async {
  SharedPreferences.setMockInitialValues({
    'reader.manga_page_turn_animation': animations,
    'reader.manga_view_mode': MangaViewMode.singlePage.storageValue,
  });
  final db = createTestDatabase();
  addTearDown(db.close);
  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(db),
      bookRepositoryProvider.overrideWithValue(_NoProgress(db)),
      mangaPagesProvider(_book.id).overrideWith(
        (ref) async => MokuroBook(
          title: 'Manga',
          imageDirPath: '/unused',
          pages: [
            for (var i = 0; i < _pageCount; i++)
              MokuroPage(
                pageIndex: i,
                imageFileName: 'p$i.png',
                imgWidth: 100,
                imgHeight: 150,
                blocks: const [],
              ),
          ],
        ),
      ),
      ocrProgressProvider(_book.id).overrideWith((ref) => Stream.value(null)),
      readerBrightnessProvider.overrideWith(FakeReaderBrightnessNotifier.new),
      proUnlockedProvider.overrideWith(() => FakeProUnlockedNotifier(false)),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: buildLocalizedTestApp(home: MangaReaderScreen(book: _book)),
    ),
  );
  await tester.pumpAndSettle();
}

/// Closes the reader and lets the progress sync's debounce run out.
Future<void> _closeReader(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 3));
}

/// The first page on screen, from the reader's own page label.
int _page(WidgetTester tester) {
  final label = tester
      .widget<ReaderPageSemantics>(find.byType(ReaderPageSemantics))
      .label;
  for (var page = 1; page <= _pageCount; page++) {
    if (label == _en.readerPageOf(page: page, total: _pageCount)) return page;
  }
  return fail('unexpected page label "$label"');
}

/// Where the pages are: a whole number while one page fills the screen.
double _position(WidgetTester tester) =>
    tester.widget<PageView>(find.byType(PageView)).controller!.page!;

/// A tap at the left edge: forward, right to left.
Future<void> _tapForward(WidgetTester tester) =>
    tester.tapAt(const Offset(20, 300));

/// A swipe to the right: forward, right to left.
Future<void> _swipeForward(WidgetTester tester) =>
    tester.flingFrom(const Offset(200, 300), const Offset(400, 0), 1000);

void main() {
  late WakelockPlusPlatformInterface originalWakelock;
  setUp(() {
    originalWakelock = WakelockPlusPlatformInterface.instance;
    WakelockPlusPlatformInterface.instance = _NoWakelock();
  });
  tearDown(() => WakelockPlusPlatformInterface.instance = originalWakelock);

  for (final (gesture, turn) in [
    ('tap', _tapForward),
    ('swipe', _swipeForward),
  ]) {
    testWidgets('Animations off: a $gesture shows the next page in the next '
        'frame', (tester) async {
      await _openReader(tester, animations: false);

      await turn(tester);
      await tester.pump();
      expect(_page(tester), 2);
      expect(_position(tester), 1.0);
      // And there it stays.
      await tester.pumpAndSettle();
      expect(_page(tester), 2);
      expect(_position(tester), 1.0);
      await _closeReader(tester);
    });

    testWidgets('Animations on: a $gesture slides to the next page', (
      tester,
    ) async {
      await _openReader(tester, animations: true);

      await turn(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(_position(tester), inExclusiveRange(0.0, 1.0));
      await tester.pumpAndSettle();
      expect(_page(tester), 2);
      expect(_position(tester), 1.0);
      await _closeReader(tester);
    });
  }
}
