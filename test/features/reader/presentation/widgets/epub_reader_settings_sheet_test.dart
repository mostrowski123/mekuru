import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/reader/data/models/reader_brightness_state.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/features/reader/presentation/widgets/reader_settings/epub_reader_settings_sheet.dart';
import 'package:mekuru/shared/widgets/settings/settings_rows.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../test_app.dart';

class _FakeBrightnessNotifier extends ReaderBrightnessNotifier {
  @override
  ReaderBrightnessState build() => const ReaderBrightnessState();

  @override
  Future<void> applyForReaderOpen() async {}

  @override
  Future<void> resetBrightness() async {}
}

Future<ProviderContainer> _pumpSheet(
  WidgetTester tester, {
  String? bookLanguage = 'ja',
  void Function(String, Object)? onSettingChanged,
}) async {
  final container = ProviderContainer(
    overrides: [
      readerBrightnessProvider.overrideWith(_FakeBrightnessNotifier.new),
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

/// The sheet's ListView builds rows lazily inside a half-height draggable
/// sheet; scroll until [finder] is built and visible before interacting.
Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    100,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders the three section headers', (tester) async {
    await _pumpSheet(tester);
    expect(find.text('This book'), findsOneWidget);
    await _scrollTo(tester, find.text('Display'));
    expect(find.text('Display'), findsOneWidget);
    await _scrollTo(tester, find.text('Behavior'));
    expect(find.text('Behavior'), findsOneWidget);
  });

  testWidgets('furigana labels come from localization', (tester) async {
    await _pumpSheet(tester);
    await _scrollTo(tester, find.text('Furigana'));
    expect(find.text('Furigana'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);
    expect(find.text('All kanji'), findsOneWidget);
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
    await _scrollTo(tester, splitFinder);
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
    await _scrollTo(tester, find.text('Font Size'));
    await tester.drag(fontSizeSlider, const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(changes, contains('font_size'));
  });
}
