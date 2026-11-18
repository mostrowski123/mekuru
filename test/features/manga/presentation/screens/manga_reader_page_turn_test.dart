import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
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

Future<void> _openReader(
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
  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(db),
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
