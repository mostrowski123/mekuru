import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/main.dart' as app;
import 'package:local_manga_ocr/local_manga_ocr.dart';
import 'package:mekuru/features/stats/presentation/widgets/activity_heatmap_card.dart';
import 'package:mekuru/features/stats/presentation/widgets/reading_time_card.dart';

import 'test_helpers.dart';

Finder _bottomNavLabel(String label) {
  return find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );
}

Finder _appBarTitle(String title) {
  return find.descendant(of: find.byType(AppBar), matching: find.text(title));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app boots and core tabs are reachable', (tester) async {
    final l10n = await loadExpectedL10n();

    await app.main();

    await pumpUntilVisible(
      tester,
      find.byType(NavigationBar),
      timeout: const Duration(seconds: 30),
    );
    // Uses the real database/native assets, unlike repository widget tests.
    // A navigation bar alone also appears when SQLite failed to initialize.
    await pumpUntilVisible(tester, find.text(l10n.libraryEmptyTitle));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await pumpUntilVisible(tester, _bottomNavLabel(l10n.navDictionary));
    await pumpUntilVisible(tester, _bottomNavLabel(l10n.navVocabulary));
    await pumpUntilVisible(tester, _bottomNavLabel(l10n.navYou));

    await tester.tap(_bottomNavLabel(l10n.navDictionary));
    await pumpUntilVisible(tester, _appBarTitle(l10n.navDictionary));
    await pumpUntilVisible(
      tester,
      find.text(l10n.dictionaryNoDictionariesTitle),
    );

    await tester.tap(_bottomNavLabel(l10n.navVocabulary));
    await pumpUntilVisible(tester, _appBarTitle(l10n.navVocabulary));
    await pumpUntilVisible(tester, find.text(l10n.vocabularyEmptyTitle));

    await tester.tap(_bottomNavLabel(l10n.navYou));
    await pumpUntilVisible(tester, _appBarTitle(l10n.navYou));
    await pumpUntilVisible(tester, find.byType(ActivityHeatmapCard));
    await tester.scrollUntilVisible(
      find.byType(ReadingTimeCard),
      250,
      scrollable: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    );
    expect(find.byType(ReadingTimeCard), findsOneWidget);
    expect(find.text(l10n.statsUnavailable), findsNothing);
    // The native OCR channel exists on Android only.
    if (LocalMangaOcr.available) {
      expect(await LocalMangaOcr.isWifiConnected(), isA<bool>());
    }

    // Settings has no navigation-bar slot of its own; it opens from the gear
    // in the You tab's app bar.
    await pumpUntilVisible(tester, find.byIcon(Icons.settings_outlined));
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await pumpUntilVisible(tester, _appBarTitle(l10n.settingsTitle));
    await pumpUntilVisible(tester, find.text(l10n.settingsSectionGeneral));
  });
}
