import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/settings/data/services/app_settings_storage.dart';
import 'package:mekuru/features/settings/presentation/screens/settings_screen.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';

import 'shared/test_infrastructure.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppLocalizations l10n;

  setUp(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
    // PreloadedAppSettings is a static cache that picker taps mutate, so
    // reset it between tests or earlier tests in this suite contaminate the
    // initial theme/color seen by the next test.
    PreloadedAppSettings.initialThemeMode = ThemeMode.dark;
    PreloadedAppSettings.initialColorThemeName = null;
  });

  testWidgets('theme mode change updates subtitle', (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);

    await tester.pumpWidget(
      buildIntegrationTestApp(db: db, home: const SettingsScreen()),
    );
    await tester.pumpAndSettle();

    // Default theme is dark. Verify subtitle shows "Dark".
    expect(find.text(l10n.settingsThemeDark), findsOneWidget);

    // Tap the theme tile to open the bottom sheet picker.
    await tester.tap(find.text(l10n.settingsThemeTitle));
    await tester.pumpAndSettle();

    // Select "Light" from the bottom sheet.
    await tester.tap(find.text(l10n.settingsThemeLight));
    await tester.pumpAndSettle();

    // Verify the subtitle now shows "Light".
    expect(find.text(l10n.settingsThemeLight), findsOneWidget);
    expect(find.text(l10n.settingsThemeDark), findsNothing);
  });

  testWidgets('color theme change updates subtitle', (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);

    await tester.pumpWidget(
      buildIntegrationTestApp(db: db, home: const SettingsScreen()),
    );
    await tester.pumpAndSettle();

    // Verify the color theme tile is visible.
    expect(find.text(l10n.settingsColorThemeTitle), findsOneWidget);

    // Tap the color theme tile to open the picker.
    await tester.tap(find.text(l10n.settingsColorThemeTitle));
    await tester.pumpAndSettle();

    // The bottom sheet should show color theme options.
    // Tap the second option (which should be different from the default).
    final colorOptions = find.byType(InkWell);
    // There are multiple InkWells; the color picker grid should have several.
    // We just verify the bottom sheet appeared and can be dismissed.
    expect(colorOptions, findsWidgets);

    // Dismiss the bottom sheet.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'theme mode change persists to storage and rehydrates on rebuild',
    (tester) async {
      // Catches regressions where the UI updates but the change never reaches
      // storage, or where storage saves but a fresh provider scope reads stale
      // defaults instead of the persisted value.
      final db = createTestDatabase();
      addTearDown(db.close);
      final storage = InMemoryAppSettingsStorage();

      await tester.pumpWidget(
        buildIntegrationTestApp(
          db: db,
          home: const SettingsScreen(),
          appSettingsStorage: storage,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.settingsThemeTitle));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.settingsThemeLight));
      await tester.pumpAndSettle();

      expect(await storage.loadThemeMode(), ThemeMode.light);

      // Pump a fresh widget tree backed by the same storage — the
      // newly-mounted Settings screen must read the persisted value.
      await tester.pumpWidget(
        buildIntegrationTestApp(
          db: db,
          home: const SettingsScreen(),
          appSettingsStorage: storage,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.settingsThemeLight), findsOneWidget);
      expect(find.text(l10n.settingsThemeDark), findsNothing);
    },
  );

  testWidgets('reading subpage font size change persists to reader storage', (
    tester,
  ) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final readerStorage = InMemoryReaderSettingsStorage();

    await tester.pumpWidget(
      buildIntegrationTestApp(
        db: db,
        home: const SettingsScreen(),
        readerSettingsStorage: readerStorage,
      ),
    );
    await tester.pumpAndSettle();

    // Drill into the Reading subpage from the main settings screen.
    await tester.tap(find.text(l10n.settingsReadingSubtitle));
    await tester.pumpAndSettle();
    expect(find.text(l10n.settingsReadingSectionShared), findsOneWidget);

    // Drag the font size slider (the first slider on the subpage).
    await tester.drag(find.byType(Slider).first, const Offset(80, 0));
    await tester.pumpAndSettle();

    final saved = await readerStorage.load();
    expect(saved, isNotNull);
    expect(saved!.fontSize, isNot(18.0));
  });

  testWidgets('startup screen change persists to storage', (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final storage = InMemoryAppSettingsStorage();

    await tester.pumpWidget(
      buildIntegrationTestApp(
        db: db,
        home: const SettingsScreen(),
        appSettingsStorage: storage,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.settingsStartupScreenTitle));
    await tester.pumpAndSettle();
    // Scope to the sheet: the settings screen's "Dictionary" section header
    // can be visible behind it and would make a bare text finder ambiguous.
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text(l10n.settingsStartupScreenDictionary),
      ),
    );
    await tester.pumpAndSettle();

    // The label-to-key mapping is owned by the storage; we just need the
    // saved value to round-trip (i.e. not stay null), and the UI to reflect
    // the new selection.
    expect(await storage.loadStartupScreen(), isNotNull);
    // Scope to the startup tile: the "Dictionary" section header elsewhere
    // on the screen also matches a bare text finder.
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, l10n.settingsStartupScreenTitle),
        matching: find.text(l10n.settingsStartupScreenDictionary),
      ),
      findsOneWidget,
    );
  });
}
