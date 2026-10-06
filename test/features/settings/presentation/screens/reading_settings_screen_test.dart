import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/presentation/providers/pro_access_provider.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/features/settings/presentation/screens/reading_settings_screen.dart';
import 'package:mekuru/shared/widgets/settings/settings_rows.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../shared/reader_settings_test_helpers.dart';
import '../../../../test_app.dart';

Future<ProviderContainer> _pumpScreen(
  WidgetTester tester, {
  bool proUnlocked = false,
}) async {
  final container = ProviderContainer(
    overrides: [
      proUnlockedProvider.overrideWith(
        () => FakeProUnlockedNotifier(proUnlocked),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: buildLocalizedTestApp(home: const ReadingSettingsScreen()),
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
    await _pumpScreen(tester);
    expect(find.text('All books'), findsOneWidget);
    await scrollSettingsTo(tester, find.text('EPUB'));
    expect(find.text('EPUB'), findsOneWidget);
    await scrollSettingsTo(tester, find.text('Manga'));
    expect(find.text('Manga'), findsOneWidget);
  });

  testWidgets('font size slider writes through the shared provider', (
    tester,
  ) async {
    final container = await _pumpScreen(tester);
    final before = container.read(readerSettingsProvider).fontSize;

    await tester.drag(find.byType(Slider).first, const Offset(80, 0));
    await tester.pumpAndSettle();

    expect(container.read(readerSettingsProvider).fontSize, isNot(before));
  });

  testWidgets('scroll view writes through and disables split text', (
    tester,
  ) async {
    final container = await _pumpScreen(tester);
    final scrollFinder = find.widgetWithText(SettingsSwitchRow, 'Scroll View');
    await scrollSettingsTo(tester, scrollFinder);
    await tester.tap(
      find.descendant(of: scrollFinder, matching: find.byType(Switch)),
    );
    await tester.pumpAndSettle();

    expect(container.read(readerSettingsProvider).scrollView, isTrue);
    final splitFinder = find.widgetWithText(
      SettingsSwitchRow,
      'Split Vertical Text',
    );
    await scrollSettingsTo(tester, splitFinder);
    expect(tester.widget<SettingsSwitchRow>(splitFinder).onChanged, isNull);
  });

  testWidgets('volume buttons choice writes through on Android', (
    tester,
  ) async {
    final container = await _pumpScreen(tester);
    expect(
      container.read(readerSettingsProvider).volumeKeyPageTurn,
      VolumeKeyPageTurn.downNext,
    );

    await tester.tap(find.text('Off'));
    await tester.pumpAndSettle();

    expect(
      container.read(readerSettingsProvider).volumeKeyPageTurn,
      VolumeKeyPageTurn.off,
    );
  });

  testWidgets('volume buttons choice is hidden on iOS', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await _pumpScreen(tester);
    expect(find.text('Volume buttons turn pages'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Pro manga tiles are hidden without Pro', (tester) async {
    await _pumpScreen(tester);
    await scrollSettingsTo(tester, find.text('Manga'));
    // Scroll to the very bottom to be sure the Pro tiles would have built.
    await tester.drag(
      find.byType(Scrollable).first,
      const Offset(0, -1200),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(find.text('White Threshold'), findsNothing);
    expect(find.text('Custom OCR Server'), findsNothing);
  });
}
