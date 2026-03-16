import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/app.dart';
import 'package:mekuru/features/backup/presentation/providers/backup_providers.dart';
import 'package:mekuru/features/manga/presentation/providers/pro_access_provider.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/main.dart' show databaseProvider;

import 'shared/test_infrastructure.dart';
import 'test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppLocalizations l10n;

  setUp(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  testWidgets('tab switching preserves dictionary search state',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    await seedDictionaries(db);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          appSettingsStorageProvider.overrideWithValue(
            InMemoryAppSettingsStorage(),
          ),
          readerSettingsStorageProvider.overrideWithValue(
            InMemoryReaderSettingsStorage(),
          ),
          proUnlockedProvider.overrideWithBuild((ref, notifier) => false),
          autoBackupCheckerProvider.overrideWith((ref) async {}),
        ],
        child: const MekuruApp(),
      ),
    );

    // Wait for the app to render.
    await pumpUntilVisible(
      tester,
      find.byType(NavigationBar),
      timeout: const Duration(seconds: 15),
    );

    // Navigate to Dictionary tab.
    await tester.tap(find.text(l10n.navDictionary));
    await tester.pumpAndSettle();

    // Search for a word.
    final searchField = find.byType(TextField);
    await tester.enterText(searchField, '食べる');
    await tester.pump(const Duration(milliseconds: 400));
    await pumpUntilVisible(
      tester,
      find.text('たべる'),
      timeout: const Duration(seconds: 10),
    );

    // Switch to Vocabulary tab.
    await tester.tap(find.text(l10n.navVocabulary));
    await tester.pumpAndSettle();

    // Verify we're on the Vocabulary tab.
    expect(find.text(l10n.vocabularyEmptyTitle), findsOneWidget);

    // Switch back to Dictionary tab.
    await tester.tap(find.text(l10n.navDictionary));
    await tester.pumpAndSettle();

    // Verify search results are preserved (IndexedStack keeps state alive).
    expect(find.text('たべる'), findsWidgets);
  });

  testWidgets('all tabs render with seeded data', (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    await seedDictionaries(db);
    await seedVocabulary(db, count: 3);
    await seedBooks(db, count: 2);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          appSettingsStorageProvider.overrideWithValue(
            InMemoryAppSettingsStorage(),
          ),
          readerSettingsStorageProvider.overrideWithValue(
            InMemoryReaderSettingsStorage(),
          ),
          proUnlockedProvider.overrideWithBuild((ref, notifier) => false),
          autoBackupCheckerProvider.overrideWith((ref) async {}),
        ],
        child: const MekuruApp(),
      ),
    );

    // Wait for the app to render with Library tab.
    await pumpUntilVisible(
      tester,
      find.byType(NavigationBar),
      timeout: const Duration(seconds: 15),
    );

    // Library tab: verify seeded books are displayed.
    await pumpUntilVisible(
      tester,
      find.text('吾輩は猫である'),
      timeout: const Duration(seconds: 10),
    );
    expect(find.text('走れメロス'), findsOneWidget);

    // Vocabulary tab: verify seeded words are displayed.
    await tester.tap(find.text(l10n.navVocabulary));
    await pumpUntilVisible(
      tester,
      find.text('食べる'),
      timeout: const Duration(seconds: 10),
    );
    expect(find.text('飲む'), findsOneWidget);

    // Settings tab: verify it renders.
    await tester.tap(find.text(l10n.navSettings));
    await pumpUntilVisible(
      tester,
      find.text(l10n.settingsTitle),
      timeout: const Duration(seconds: 10),
    );
    expect(find.text(l10n.settingsSectionGeneral), findsOneWidget);
  });
}
