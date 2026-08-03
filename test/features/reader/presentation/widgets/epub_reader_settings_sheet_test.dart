import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/features/reader/presentation/widgets/reader_settings/epub_reader_settings_sheet.dart';
import 'package:mekuru/shared/widgets/settings/settings_rows.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../shared/reader_settings_test_helpers.dart';
import '../../../../test_app.dart';

Future<ProviderContainer> _pumpSheet(
  WidgetTester tester, {
  String? bookLanguage = 'ja',
  void Function(String, Object)? onSettingChanged,
}) async {
  final container = ProviderContainer(
    overrides: [
      readerBrightnessProvider.overrideWith(FakeReaderBrightnessNotifier.new),
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
            pageProgressionDirection: null,
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
    ]);
  });

  testWidgets('a stored aboveLevel displays as the all segment', (
    tester,
  ) async {
    final container = await _pumpSheet(tester);
    container
        .read(readerSettingsProvider.notifier)
        .setFuriganaMode(FuriganaMode.aboveLevel);
    await tester.pumpAndSettle();

    await scrollSettingsTo(tester, find.text('Furigana'));
    final row = tester.widget<SettingsSegmentedRow<FuriganaMode>>(
      find.byType(SettingsSegmentedRow<FuriganaMode>),
    );
    expect(row.selected, FuriganaMode.all);
  });

  testWidgets('tapping all while aboveLevel is stored is a no-op', (
    tester,
  ) async {
    final changes = <String>[];
    final container = await _pumpSheet(
      tester,
      onSettingChanged: (setting, value) => changes.add(setting),
    );
    container
        .read(readerSettingsProvider.notifier)
        .setFuriganaMode(FuriganaMode.aboveLevel);
    await tester.pumpAndSettle();

    await scrollSettingsTo(tester, find.text('All kanji'));
    await tester.tap(find.text('All kanji'));
    await tester.pumpAndSettle();

    expect(
      container.read(readerSettingsProvider).furiganaMode,
      FuriganaMode.aboveLevel,
    );
    expect(changes, isNot(contains('furigana_mode')));
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
