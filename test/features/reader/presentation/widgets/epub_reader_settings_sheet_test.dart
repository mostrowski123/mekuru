import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/features/reader/presentation/widgets/reader_settings/epub_reader_settings_sheet.dart';
import 'package:mekuru/features/wanikani/presentation/providers/wanikani_providers.dart';
import 'package:mekuru/shared/widgets/settings/settings_rows.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../shared/reader_settings_test_helpers.dart';
import '../../../../shared/wanikani_test_fakes.dart';
import '../../../../test_app.dart';

Future<ProviderContainer> _pumpSheet(
  WidgetTester tester, {
  String? bookLanguage = 'ja',
  void Function(String, Object)? onSettingChanged,
  FakeWanikaniStorage? wanikaniStorage,
}) async {
  final container = ProviderContainer(
    overrides: [
      readerBrightnessProvider.overrideWith(FakeReaderBrightnessNotifier.new),
      if (wanikaniStorage != null)
        wanikaniStorageProvider.overrideWithValue(wanikaniStorage),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: buildLocalizedTestApp(
        home: Scaffold(
          body: EpubReaderSettingsSheet(
            bookLanguage: bookLanguage,
            onSettingChanged: onSettingChanged ?? (_, _) {},
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

  testWidgets('renders the three section headers', (tester) async {
    await _pumpSheet(tester);
    expect(find.text('This book'), findsOneWidget);
    await scrollSettingsTo(tester, find.text('Display'));
    expect(find.text('Display'), findsOneWidget);
    await scrollSettingsTo(tester, find.text('Behavior'));
    expect(find.text('Behavior'), findsOneWidget);
  });

  testWidgets('furigana labels come from localization', (tester) async {
    await _pumpSheet(tester);
    await scrollSettingsTo(tester, find.text('Furigana'));
    expect(find.text('Furigana'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);
    expect(find.text('Book'), findsOneWidget);
    expect(find.text('All kanji'), findsOneWidget);
  });

  testWidgets('furigana defaults to the book segment', (tester) async {
    await _pumpSheet(tester);
    await scrollSettingsTo(tester, find.text('Furigana'));
    final row = tester.widget<SettingsSegmentedRow<FuriganaMode>>(
      find.byType(SettingsSegmentedRow<FuriganaMode>),
    );
    expect(row.selected, FuriganaMode.book);
    expect(row.segments.map((s) => s.value).toList(), [
      FuriganaMode.hide,
      FuriganaMode.book,
      FuriganaMode.all,
      FuriganaMode.aboveLevel,
      FuriganaMode.wanikani,
    ]);
  });

  testWidgets('WaniKani mode without synced kanji offers to link', (
    tester,
  ) async {
    final container = await _pumpSheet(tester);
    await scrollSettingsTo(tester, find.text('Furigana'));
    expect(find.byKey(const Key('reader-wanikani-link-prompt')), findsNothing);

    container
        .read(readerSettingsProvider.notifier)
        .setFuriganaMode(FuriganaMode.wanikani);
    await tester.pumpAndSettle();

    await scrollSettingsTo(tester, find.text('Link your WaniKani account'));
    expect(
      find.byKey(const Key('reader-wanikani-link-prompt')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('reader-wanikani-stage')), findsNothing);
  });

  testWidgets('WaniKani mode with synced kanji reveals the stage picker', (
    tester,
  ) async {
    final changes = <String>[];
    final storage = FakeWanikaniStorage(
      token: 'tok',
      snapshot: snapshotAt(DateTime.utc(2026, 9, 10)),
    );
    final container = await _pumpSheet(
      tester,
      onSettingChanged: (setting, value) => changes.add(setting),
      wanikaniStorage: storage,
    );
    await container.read(wanikaniProvider.notifier).loadPersistedSettings();
    container
        .read(readerSettingsProvider.notifier)
        .setFuriganaMode(FuriganaMode.wanikani);
    await tester.pumpAndSettle();

    await scrollSettingsTo(tester, find.text('Known kanji'));
    expect(find.byKey(const Key('reader-wanikani-link-prompt')), findsNothing);
    expect(find.text('Burned only'), findsOneWidget);

    await tester.tap(find.byKey(const Key('reader-wanikani-stage')));
    await tester.pumpAndSettle();
    // Every option spells out the stages it covers.
    expect(find.text('Which kanji count as known?'), findsOneWidget);
    expect(find.text('Guru, Master, Enlightened and Burned'), findsOneWidget);
    await tester.tap(find.text('Guru or higher'));
    await tester.pumpAndSettle();

    expect(container.read(readerSettingsProvider).furiganaWanikaniMinStage, 5);
    expect(changes, contains('furigana_wanikani_stage'));
    expect(find.text('Guru or higher'), findsOneWidget);
  });

  testWidgets('JLPT mode reveals the level picker and sets the level', (
    tester,
  ) async {
    final changes = <String>[];
    final container = await _pumpSheet(
      tester,
      onSettingChanged: (setting, value) => changes.add(setting),
    );

    await scrollSettingsTo(tester, find.text('Furigana'));
    expect(find.text('Furigana for kanji above'), findsNothing);

    container
        .read(readerSettingsProvider.notifier)
        .setFuriganaMode(FuriganaMode.aboveLevel);
    await tester.pumpAndSettle();

    await scrollSettingsTo(tester, find.text('Furigana for kanji above'));
    await tester.tap(find.text('N2'));
    await tester.pumpAndSettle();

    expect(container.read(readerSettingsProvider).furiganaJlptLevel, 2);
    expect(changes, contains('furigana_jlpt_level'));
  });

  testWidgets('vertical text switch is disabled for non-CJK books', (
    tester,
  ) async {
    await _pumpSheet(tester, bookLanguage: 'en');
    final row = tester.widget<SettingsSwitchRow>(
      find.byType(SettingsSwitchRow).first,
    );
    expect(row.onChanged, isNull);
  });

  testWidgets('split vertical text is disabled when vertical text is off', (
    tester,
  ) async {
    final container = await _pumpSheet(tester);
    container.read(readerSettingsProvider.notifier).setVerticalText(false);
    await tester.pumpAndSettle();

    final splitFinder = find.widgetWithText(
      SettingsSwitchRow,
      'Split Vertical Text',
    );
    await scrollSettingsTo(tester, splitFinder);
    final splitRow = tester.widget<SettingsSwitchRow>(splitFinder);
    expect(splitRow.onChanged, isNull);
  });

  testWidgets('changing font size reports telemetry with the setting name', (
    tester,
  ) async {
    final changes = <String>[];
    await _pumpSheet(
      tester,
      onSettingChanged: (setting, value) => changes.add(setting),
    );

    final fontSizeSlider = find.descendant(
      of: find.ancestor(
        of: find.text('Font Size'),
        matching: find.byType(SettingsSliderRow),
      ),
      matching: find.byType(Slider),
    );
    await scrollSettingsTo(tester, find.text('Font Size'));
    await tester.drag(fontSizeSlider, const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(changes, contains('font_size'));
  });
}
