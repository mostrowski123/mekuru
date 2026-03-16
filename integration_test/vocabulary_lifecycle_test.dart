import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/vocabulary/presentation/screens/vocabulary_screen.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';

import 'shared/test_infrastructure.dart';
import 'test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppLocalizations l10n;

  setUp(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  testWidgets('vocabulary list displays seeded words', (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    await seedVocabulary(db, count: 5);

    await tester.pumpWidget(
      buildIntegrationTestApp(
        db: db,
        home: const VocabularyScreen(),
      ),
    );

    // Wait for the reactive stream to deliver data.
    await pumpUntilVisible(
      tester,
      find.text('食べる'),
      timeout: const Duration(seconds: 10),
    );

    // Verify all 5 seeded words are displayed.
    expect(find.text('食べる'), findsOneWidget);
    expect(find.text('飲む'), findsOneWidget);
    expect(find.text('走る'), findsOneWidget);
    expect(find.text('食べ物'), findsOneWidget);
    expect(find.text('大きい'), findsOneWidget);
  });

  testWidgets('vocabulary search filters correctly', (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    await seedVocabulary(db, count: 5);

    await tester.pumpWidget(
      buildIntegrationTestApp(
        db: db,
        home: const VocabularyScreen(),
      ),
    );

    await pumpUntilVisible(
      tester,
      find.text('食べる'),
      timeout: const Duration(seconds: 10),
    );

    // Enter search query that should match "食べる" and "食べ物" only.
    final searchField = find.byType(TextField);
    await tester.enterText(searchField, '食べ');
    await tester.pumpAndSettle();

    // Words containing "食べ" should be visible.
    expect(find.text('食べる'), findsOneWidget);
    expect(find.text('食べ物'), findsOneWidget);

    // Words not matching should be gone.
    expect(find.text('飲む'), findsNothing);
    expect(find.text('走る'), findsNothing);
    expect(find.text('大きい'), findsNothing);
  });

  testWidgets('swipe to delete shows SnackBar with undo', (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    await seedVocabulary(db, count: 3);

    await tester.pumpWidget(
      buildIntegrationTestApp(
        db: db,
        home: const VocabularyScreen(),
      ),
    );

    await pumpUntilVisible(
      tester,
      find.text('食べる'),
      timeout: const Duration(seconds: 10),
    );

    // Swipe the first word (食べる) to delete.
    final wordTile = find.text('食べる');
    await tester.fling(wordTile, const Offset(-500, 0), 1500);
    await tester.pumpAndSettle();

    // Verify SnackBar appears with the deleted word text.
    expect(
      find.text(l10n.vocabularyDeletedWord(expression: '食べる')),
      findsOneWidget,
    );

    // Verify the word is removed from the list.
    // (The ListTile text should no longer be in the vocabulary list.)
    // Note: the SnackBar might contain the expression too, so we check
    // that the Dismissible-based tile is gone.
    expect(find.byKey(const Key('vocab_1')), findsNothing);

    // Tap undo.
    await tester.tap(find.text(l10n.commonUndo));
    await tester.pumpAndSettle();

    // Wait for the restored word to re-appear from the reactive stream.
    await pumpUntilVisible(
      tester,
      find.byKey(const Key('vocab_1')),
      timeout: const Duration(seconds: 10),
    );
  });
}
