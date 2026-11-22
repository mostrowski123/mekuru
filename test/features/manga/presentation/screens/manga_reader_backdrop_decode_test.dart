// In Spread view the Auto and Blur backgrounds take the page on screen from
// the image the spread already decoded: a page turn reads and decodes each
// page once, also for a book in the user's folder, whose pages come through
// a method channel.

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
import 'package:mekuru/features/manga/presentation/widgets/manga_backdrop.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/features/reader/presentation/widgets/reader_page_navigation.dart';
import 'package:mekuru/l10n/generated/app_localizations_en.dart';
import 'package:mekuru/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

import '../../../../shared/reader_settings_test_helpers.dart';
import '../../../../shared/saf_image_fixtures.dart';
import '../../../../shared/test_database.dart';
import '../../../../test_app.dart';

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

final _book = Book(
  id: 1,
  isFavorite: false,
  title: 'Manga',
  filePath: '/unused',
  bookType: 'manga',
  totalPages: 5,
  readProgress: 0,
  dateAdded: DateTime(2026, 11, 22),
);

/// Opens five portrait pages from the user's folder in Spread view, read
/// right to left: [0], [2,1], [4,3].
Future<void> _openReader(
  WidgetTester tester,
  MangaBackground background,
) async {
  SharedPreferences.setMockInitialValues({
    'reader.manga_page_turn_animation': false,
    'reader.manga_view_mode': MangaViewMode.twoPageSpread.storageValue,
    'reader.manga_background': background.storageValue,
  });
  final db = createTestDatabase();
  addTearDown(db.close);
  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(db),
      bookRepositoryProvider.overrideWithValue(_NoProgress(db)),
      mangaPagesProvider(_book.id).overrideWith((ref) async {
        // After the saved settings, so no page is shown in Single view first.
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return MokuroBook(
          title: 'Manga',
          imageDirPath: '/unused',
          safTreeUri: 'content://tree/test',
          safImageDirRelativePath: 'imgs',
          pages: [
            for (var i = 0; i < 5; i++)
              MokuroPage(
                pageIndex: i,
                imageFileName: 'p$i.png',
                imgWidth: 100,
                imgHeight: 150,
                blocks: const [],
              ),
          ],
        );
      }),
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

void main() {
  late WakelockPlusPlatformInterface originalWakelock;
  late List<String> readPaths;

  setUp(() {
    originalWakelock = WakelockPlusPlatformInterface.instance;
    WakelockPlusPlatformInterface.instance = NoWakelock();
    readPaths = stubSafImageReads();
  });
  tearDown(() {
    WakelockPlusPlatformInterface.instance = originalWakelock;
    clearSafImageStub();
  });

  /// How many times each page was read, by page index.
  Map<int, int> reads() => {
    for (var i = 0; i < 5; i++)
      i: readPaths.where((p) => p == 'imgs/p$i.png').length,
  };

  for (final background in [MangaBackground.blur, MangaBackground.auto]) {
    testWidgets('Spread view, ${background.name} background: each page on '
        'screen is read once', (tester) async {
      await _openReader(tester, background);
      expect(find.byType(MangaBackdrop), findsOneWidget);
      // The cover, alone on screen, and the next spread, built ahead.
      final onOpen = reads();

      // A tap at the left edge: forward, right to left.
      await tester.tapAt(const Offset(20, 300));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ReaderPageSemantics>(find.byType(ReaderPageSemantics))
            .label,
        AppLocalizationsEn().readerPageOf(page: 2, total: 5),
      );
      // Pages 1 and 2 on screen, the background showing page 1, and the
      // spread after them built ahead.
      expect(
        [onOpen, reads()],
        [
          {0: 1, 1: 1, 2: 1, 3: 0, 4: 0},
          {0: 1, 1: 1, 2: 1, 3: 1, 4: 1},
        ],
      );

      // Closing the reader lets the progress sync's debounce run out.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    });
  }
}
