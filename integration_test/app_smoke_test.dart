import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/settings/data/services/app_settings_storage.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/main.dart' as app;

import 'test_helpers.dart';

Future<AppLocalizations> _loadExpectedL10n() async {
  final locale = resolveSupportedAppLocale(
    WidgetsBinding.instance.platformDispatcher.locale,
    AppLocalizations.supportedLocales,
  );
  return AppLocalizations.delegate.load(locale);
}

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
    final l10n = await _loadExpectedL10n();

    await app.main();

    await pumpUntilVisible(
      tester,
      find.byType(NavigationBar),
      timeout: const Duration(seconds: 30),
    );
    await pumpUntilVisible(tester, _bottomNavLabel(l10n.navDictionary));
    await pumpUntilVisible(tester, _bottomNavLabel(l10n.navVocabulary));
    await pumpUntilVisible(tester, _bottomNavLabel(l10n.navSettings));

    await tester.tap(_bottomNavLabel(l10n.navDictionary));
    await pumpUntilVisible(tester, _appBarTitle(l10n.navDictionary));
    await pumpUntilVisible(
      tester,
      find.text(l10n.dictionaryNoDictionariesTitle),
    );

    await tester.tap(_bottomNavLabel(l10n.navVocabulary));
    await pumpUntilVisible(tester, _appBarTitle(l10n.navVocabulary));
    await pumpUntilVisible(tester, find.text(l10n.vocabularyEmptyTitle));

    await tester.tap(_bottomNavLabel(l10n.navSettings));
    await pumpUntilVisible(tester, _appBarTitle(l10n.settingsTitle));
    await pumpUntilVisible(tester, find.text(l10n.settingsSectionGeneral));
  });
}
