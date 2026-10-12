import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/presentation/providers/manga_reader_providers.dart';
import 'package:mekuru/features/manga/presentation/providers/pro_access_provider.dart';
import 'package:mekuru/features/manga/presentation/widgets/manga_reader_settings_sheet.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/shared/widgets/settings/settings_rows.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../shared/reader_settings_test_helpers.dart';
import '../../../../test_app.dart';

Future<ProviderContainer> _pumpSheet(
  WidgetTester tester, {
  bool proUnlocked = true,
  void Function(String, Object)? onSettingChanged,
  ValueChanged<bool>? onAutoCropToggled,
  ValueNotifier<ReaderDirection?>? bookDirection,
  ValueNotifier<bool>? spreadShift,
}) async {
  final container = ProviderContainer(
    overrides: [
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
      child: buildLocalizedTestApp(
        home: Scaffold(
          body: MangaReaderSettingsSheet(
            hasComputedAutoCrop: false,
            onAutoCropToggled: onAutoCropToggled ?? (_) {},
            onAutoCropRerun: () {},
            onUnlockPro: () {},
            onSettingChanged: onSettingChanged ?? (_, _) {},
            bookDirection: bookDirection ?? ValueNotifier(null),
            spreadShift: spreadShift ?? ValueNotifier(false),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('a manga picks its own direction under This book', (
    tester,
  ) async {
    // Null: the book follows the global setting (right to left) for now.
    final bookDirection = ValueNotifier<ReaderDirection?>(null);
    addTearDown(bookDirection.dispose);
    final changes = <String>[];
    final container = await _pumpSheet(
      tester,
      bookDirection: bookDirection,
      onSettingChanged: (setting, value) => changes.add(setting),
    );
    expect(find.text('This book'), findsOneWidget);
    await scrollSettingsTo(
      tester,
      find.byType(SegmentedButton<ReaderDirection>),
    );
    final selected = tester
        .widget<SegmentedButton<ReaderDirection>>(
          find.byType(SegmentedButton<ReaderDirection>),
        )
        .selected;
    expect(selected, {ReaderDirection.rtl});

    await tester.tap(find.text('Left to Right'));
    await tester.pumpAndSettle();

    expect(bookDirection.value, ReaderDirection.ltr);
    expect(
      container.read(readerSettingsProvider).mangaReadingDirection,
      ReaderDirection.rtl,
    );
    expect(changes, ['book_direction']);
  });

  testWidgets('toggling the debug overlay does not close the sheet', (
    tester,
  ) async {
    final container = await _pumpSheet(tester);
    final debugFinder = find.widgetWithText(
      SettingsSwitchRow,
      'Debug Word Overlay',
    );
    await scrollSettingsTo(tester, debugFinder);
    await tester.tap(debugFinder);
    await tester.pumpAndSettle();

    // The sheet content is still mounted and the provider was updated.
    expect(find.byType(MangaReaderSettingsSheet), findsOneWidget);
    expect(container.read(mangaDebugWordOverlayProvider), isTrue);
  });

  testWidgets('non-Pro users see a disabled auto-crop tile with Unlock', (
    tester,
  ) async {
    await _pumpSheet(tester, proUnlocked: false);
    await scrollSettingsTo(tester, find.text('Unlock'));
    expect(find.text('Unlock'), findsOneWidget);
    expect(find.widgetWithText(SettingsSwitchRow, 'Auto-Crop'), findsNothing);
  });

  testWidgets('view mode change fires telemetry', (tester) async {
    final changes = <String>[];
    await _pumpSheet(
      tester,
      onSettingChanged: (setting, value) => changes.add(setting),
    );
    await scrollSettingsTo(tester, find.byType(SegmentedButton<MangaViewMode>));
    await tester.tap(find.text('Scroll'));
    await tester.pumpAndSettle();
    expect(changes, contains('view_mode'));
  });

  testWidgets('spread detection switch turns it off', (tester) async {
    final changes = <String>[];
    final container = await _pumpSheet(
      tester,
      onSettingChanged: (setting, value) => changes.add(setting),
    );
    final row = find.widgetWithText(
      SettingsSwitchRow,
      'Detect two-page spreads',
    );
    await scrollSettingsTo(tester, row);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(container.read(readerSettingsProvider).mangaDetectSpreads, isFalse);
    expect(changes, contains('detect_spreads'));
  });

  testWidgets('shifting pairs shows only in Spread view, for this book', (
    tester,
  ) async {
    final shift = ValueNotifier(false);
    addTearDown(shift.dispose);
    final container = await _pumpSheet(tester, spreadShift: shift);
    final row = find.widgetWithText(
      SettingsSwitchRow,
      'Shift pairs by one page',
    );
    expect(row, findsNothing);

    container
        .read(readerSettingsProvider.notifier)
        .setMangaViewMode(MangaViewMode.twoPageSpread);
    await tester.pumpAndSettle();
    await scrollSettingsTo(tester, row);
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(shift.value, isTrue);
  });
}
