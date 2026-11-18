import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// Records the places the reader saves.
class _Progress extends BookRepository {
  _Progress(super.db);

  final saved = <String>[];

  @override
  Future<void> updateProgress(
    int bookId,
    String cfi, {
    double? progress,
    String? href,
    double? hrefProgression,
  }) async {
    saved.add(cfi);
  }
}

const _picture = Key('page-turn-picture');
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

Future<_Progress> _openReader(
  WidgetTester tester, {
  required PageTurnStyle style,
  MangaViewMode viewMode = MangaViewMode.singlePage,
}) async {
  SharedPreferences.setMockInitialValues({
    'reader.page_turn_style': style.name,
    'reader.manga_view_mode': viewMode.storageValue,
  });
  final db = createTestDatabase();
  addTearDown(db.close);
  final progress = _Progress(db);
  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(db),
      bookRepositoryProvider.overrideWithValue(progress),
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
  return progress;
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

void main() {
  late WakelockPlusPlatformInterface originalWakelock;
  setUp(() {
    originalWakelock = WakelockPlusPlatformInterface.instance;
    WakelockPlusPlatformInterface.instance = _NoWakelock();
  });
  tearDown(() => WakelockPlusPlatformInterface.instance = originalWakelock);

  testWidgets('a curl covers the page, jumps underneath and clears', (
    tester,
  ) async {
    await _openReader(tester, style: PageTurnStyle.curl);
    expect(_page(tester), 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pump(); // the picture is up
    expect(find.byKey(_picture), findsOneWidget);
    await tester.pump(); // the page jumps under it
    expect(_page(tester), 2);
    expect(find.byKey(_picture), findsOneWidget, reason: 'still curling');

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.byKey(_picture), findsNothing);
    expect(_page(tester), 2);

    // And back.
    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await tester.pump();
    expect(find.byKey(_picture), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byKey(_picture), findsNothing);
    expect(_page(tester), 1);
    await _closeReader(tester);
  });

  testWidgets('a curl follows a finger dragged across the page', (
    tester,
  ) async {
    final progress = await _openReader(tester, style: PageTurnStyle.curl);
    final width = tester.getSize(find.byType(MangaReaderScreen)).width;

    // Manga reads right to left: dragging rightwards turns forward.
    final finger = await tester.startGesture(Offset(width * 0.3, 300));
    await finger.moveBy(const Offset(30, 0));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(_picture), findsOneWidget);
    expect(_page(tester), 2, reason: 'the next page is underneath');
    expect(progress.saved, isEmpty, reason: 'only peeked at so far');

    // Held still, the picture stays under the finger.
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(_picture), findsOneWidget);

    await finger.moveBy(Offset(width * 0.3, 0));
    await finger.up();
    await tester.pumpAndSettle();
    expect(find.byKey(_picture), findsNothing);
    expect(_page(tester), 2);
    expect(progress.saved, ['1'], reason: 'the turn is saved once, at its end');
    await _closeReader(tester);
  });

  testWidgets('a short drag puts the page back', (tester) async {
    final progress = await _openReader(tester, style: PageTurnStyle.curl);
    final width = tester.getSize(find.byType(MangaReaderScreen)).width;

    final finger = await tester.startGesture(Offset(width * 0.3, 300));
    await finger.moveBy(Offset(width * 0.05, 0));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(_picture), findsOneWidget);
    expect(_page(tester), 2);

    await finger.up();
    await tester.pumpAndSettle();
    expect(find.byKey(_picture), findsNothing);
    expect(_page(tester), 1);
    expect(progress.saved, isEmpty, reason: 'nothing was read or saved');
    await _closeReader(tester);
  });

  testWidgets('a drag off the first page does nothing', (tester) async {
    await _openReader(tester, style: PageTurnStyle.curl);
    final width = tester.getSize(find.byType(MangaReaderScreen)).width;

    // Leftwards is backwards in a right-to-left book.
    final finger = await tester.startGesture(Offset(width * 0.7, 300));
    await finger.moveBy(Offset(-width * 0.3, 0));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(_picture), findsNothing);
    await finger.up();
    await tester.pumpAndSettle();
    expect(_page(tester), 1);
    await _closeReader(tester);
  });

  testWidgets('no curl at either end of the book', (tester) async {
    await _openReader(tester, style: PageTurnStyle.curl);

    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await tester.pump();
    expect(find.byKey(_picture), findsNothing);
    expect(_page(tester), 1);

    for (var page = 2; page <= _pageCount; page++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pumpAndSettle();
      expect(_page(tester), page);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pump();
    expect(find.byKey(_picture), findsNothing);
    await tester.pumpAndSettle();
    expect(_page(tester), _pageCount);
    await _closeReader(tester);
  });

  testWidgets('a curl turns a whole spread', (tester) async {
    await _openReader(
      tester,
      style: PageTurnStyle.curl,
      viewMode: MangaViewMode.twoPageSpread,
    );
    final first = _page(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pump();
    expect(find.byKey(_picture), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byKey(_picture), findsNothing);
    expect(_page(tester), greaterThan(first));
    await _closeReader(tester);
  });

  testWidgets('slide and none take no picture', (tester) async {
    for (final style in [PageTurnStyle.slide, PageTurnStyle.none]) {
      await _openReader(tester, style: style);

      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pump();
      expect(find.byKey(_picture), findsNothing, reason: '$style');
      if (style == PageTurnStyle.none) {
        expect(_page(tester), 2, reason: 'no animation to wait for');
      }
      await tester.pumpAndSettle();
      expect(_page(tester), 2, reason: '$style');
      await _closeReader(tester);
    }
  });
}
