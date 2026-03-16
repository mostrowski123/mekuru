import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/dictionary/presentation/screens/dictionary_search_screen.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';

import 'shared/test_infrastructure.dart';
import 'test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppLocalizations l10n;

  setUp(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  testWidgets('search finds results and displays them', (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    await seedDictionaries(db);

    await tester.pumpWidget(
      buildIntegrationTestApp(
        db: db,
        home: const DictionarySearchScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // Enter a search term.
    final searchField = find.byType(TextField);
    await tester.enterText(searchField, '食べる');
    // Wait for the 300ms debounce + search execution.
    await tester.pump(const Duration(milliseconds: 400));
    // Wait for the dictionary source label to appear, confirming results loaded.
    await pumpUntilVisible(
      tester,
      find.text('JMdict'),
      timeout: const Duration(seconds: 10),
    );
    await tester.pumpAndSettle();

    // Verify dictionary source name appears in results.
    expect(find.text('JMdict'), findsWidgets);
  });

  testWidgets('search with no matches shows empty state', (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    await seedDictionaries(db);

    await tester.pumpWidget(
      buildIntegrationTestApp(
        db: db,
        home: const DictionarySearchScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // Enter a nonsense search term.
    final searchField = find.byType(TextField);
    await tester.enterText(searchField, 'xxxyyy');
    await tester.pump(const Duration(milliseconds: 400));
    await pumpUntilVisible(
      tester,
      find.text(l10n.dictionaryNoResultsFound),
      timeout: const Duration(seconds: 10),
    );

    expect(find.text(l10n.dictionaryNoResultsFound), findsOneWidget);
  });

  testWidgets('search history records and replays', (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    await seedDictionaries(db);

    await tester.pumpWidget(
      buildIntegrationTestApp(
        db: db,
        home: const DictionarySearchScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // Search for a word so it gets recorded in history.
    final searchField = find.byType(TextField);
    await tester.enterText(searchField, '食べる');
    await tester.pump(const Duration(milliseconds: 400));
    await pumpUntilVisible(
      tester,
      find.text('JMdict'),
      timeout: const Duration(seconds: 10),
    );

    // Clear the search field to reveal history.
    final clearButton = find.byIcon(Icons.clear);
    await tester.tap(clearButton);
    await tester.pumpAndSettle();

    // Verify the "Recent" section and the history entry.
    await pumpUntilVisible(
      tester,
      find.text(l10n.dictionaryRecent),
      timeout: const Duration(seconds: 5),
    );
    expect(find.text('食べる'), findsOneWidget);

    // Tap the history item to re-search.
    await tester.tap(find.text('食べる'));
    await tester.pump(const Duration(milliseconds: 400));
    await pumpUntilVisible(
      tester,
      find.text('JMdict'),
      timeout: const Duration(seconds: 10),
    );

    // Results should be visible again.
    expect(find.text('JMdict'), findsWidgets);
  });
}
