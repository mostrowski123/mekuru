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
import 'package:mekuru/features/manga/presentation/widgets/manga_reader_settings_sheet.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/l10n/generated/app_localizations_en.dart';
import 'package:mekuru/main.dart';
import 'package:mekuru/shared/widgets/settings/settings_rows.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

import '../../../../shared/reader_settings_test_helpers.dart';
import '../../../../shared/test_database.dart';
import '../../../../test_app.dart';

/// Stands in for the page-image scan: computing gives the pages the reader
/// loads next their crop bounds.
class _CropRepository extends BookRepository {
  _CropRepository(super.db);
  var computeCalls = 0;
  var computed = false;

  @override
  Future<bool> ensureMangaAutoCropComputed(
    Book book, {
    bool force = false,
    int whiteThreshold = 240,
  }) async {
    computeCalls++;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    computed = true;
    return true;
  }
}

class _NoWakelock extends WakelockPlusPlatformInterface {
  @override
  bool get isMock => true;

  @override
  Future<bool> get enabled async => false;

  @override
  Future<void> toggle({required bool enable}) async {}
}

final _en = AppLocalizationsEn();
final _offer = find.text(_en.mangaAutoCropComputeTitle);

final _book = Book(
  id: 1,
  title: 'Manga',
  filePath: '/unused',
  bookType: 'manga',
  totalPages: 1,
  readProgress: 0,
  dateAdded: DateTime(2026, 10, 7),
);

Future<(_CropRepository, ProviderContainer)> _openReader(
  WidgetTester tester, {
  bool autoCropOn = true,
  bool proUnlocked = true,
  bool hasBounds = false,
}) async {
  SharedPreferences.setMockInitialValues({
    'reader.manga_auto_crop': autoCropOn,
  });
  final db = createTestDatabase();
  addTearDown(db.close);
  final repository = _CropRepository(db);
  MokuroBook pages() {
    final bounded = hasBounds || repository.computed;
    return MokuroBook(
      title: 'Manga',
      imageDirPath: '/unused',
      autoCropVersion: bounded ? MokuroBook.currentAutoCropVersion : 0,
      pages: [
        MokuroPage(
          pageIndex: 0,
          imageFileName: 'p0.png',
          imgWidth: 100,
          imgHeight: 150,
          blocks: const [],
          contentBounds: bounded ? const Rect.fromLTRB(5, 5, 95, 145) : null,
        ),
      ],
    );
  }

  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(db),
      bookRepositoryProvider.overrideWithValue(repository),
      mangaPagesProvider(_book.id).overrideWith((ref) async {
        // A reload keeps showing the old pages while the cache is read.
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return pages();
      }),
      ocrProgressProvider(_book.id).overrideWith((ref) => Stream.value(null)),
      readerBrightnessProvider.overrideWith(FakeReaderBrightnessNotifier.new),
      proUnlockedProvider.overrideWith(
        () => FakeProUnlockedNotifier(proUnlocked),
      ),
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
  return (repository, container);
}

/// Taps Continue on the offer. The first pump builds the progress dialog
/// while the scan is still running, as with a real scan.
Future<void> _confirm(WidgetTester tester) async {
  await tester.tap(find.text(_en.commonContinue));
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  late WakelockPlusPlatformInterface originalWakelock;
  setUp(() {
    originalWakelock = WakelockPlusPlatformInterface.instance;
    WakelockPlusPlatformInterface.instance = _NoWakelock();
  });
  tearDown(() => WakelockPlusPlatformInterface.instance = originalWakelock);

  testWidgets('a book opened with Auto-Crop on but no bounds is offered the '
      'computation', (tester) async {
    final (repository, _) = await _openReader(tester);
    expect(_offer, findsOneWidget);

    await _confirm(tester);

    expect(repository.computeCalls, 1);
    expect(_offer, findsNothing);
  });

  testWidgets('a cancelled offer is not repeated when the pages reload', (
    tester,
  ) async {
    final (repository, container) = await _openReader(tester);
    await tester.tap(find.text(_en.commonCancel));
    await tester.pumpAndSettle();

    container.invalidate(mangaPagesProvider(_book.id));
    await tester.pumpAndSettle();

    expect(_offer, findsNothing);
    expect(repository.computeCalls, 0);
  });

  testWidgets('no offer for a book with bounds, without Pro, or with the '
      'switch off', (tester) async {
    for (final (hasBounds, proUnlocked, autoCropOn) in [
      (true, true, true),
      (false, false, true),
      (false, true, false),
    ]) {
      final (repository, _) = await _openReader(
        tester,
        hasBounds: hasBounds,
        proUnlocked: proUnlocked,
        autoCropOn: autoCropOn,
      );
      expect(_offer, findsNothing);
      expect(repository.computeCalls, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('turning the switch on computes once, without a second offer', (
    tester,
  ) async {
    final (repository, _) = await _openReader(tester, autoCropOn: false);
    await tester.tapAt(tester.getCenter(find.byType(MangaReaderScreen)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(_en.settingsTitle));
    await tester.pumpAndSettle();
    final autoCropSwitch = find.widgetWithText(
      SettingsSwitchRow,
      _en.proFeatureAutoCropTitle,
    );
    await tester.scrollUntilVisible(
      autoCropSwitch,
      100,
      scrollable: find
          .descendant(
            of: find.byType(MangaReaderSettingsSheet),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(autoCropSwitch);
    await tester.pumpAndSettle();

    expect(_offer, findsOneWidget);
    await _confirm(tester);

    expect(repository.computeCalls, 1);
    expect(_offer, findsNothing);
  });
}
