import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/ankidroid/data/models/anki_note_data.dart';
import 'package:mekuru/features/ankidroid/data/models/ankidroid_config.dart';
import 'package:mekuru/features/ankidroid/data/services/ankidroid_service.dart';
import 'package:mekuru/features/ankidroid/presentation/providers/ankidroid_providers.dart';
import 'package:mekuru/features/ankidroid/presentation/screens/anki_card_creation_screen.dart';
import 'package:mekuru/main.dart';

import '../../../../shared/test_database.dart';
import '../../../../test_app.dart';

/// Fake AnkiDroid backend: connected, two decks, and a duplicate that only
/// exists in the "Mining" deck (id 2).
class _FakeAnkidroidService extends AnkidroidService {
  final List<({int modelId, int deckId, String firstFieldValue})>
  duplicateChecks = [];

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<bool> init() async => true;

  @override
  Future<List<String>> getFieldList(int modelId) async => ['Front', 'Back'];

  @override
  Future<Map<int, String>> getDeckList() async => {1: 'Default', 2: 'Mining'};

  @override
  Future<int?> addNote({
    required int modelId,
    required int deckId,
    required List<String> fields,
    List<String> tags = const ['mekuru'],
  }) async => 42;

  @override
  Future<bool> hasDuplicateInDeck({
    required int modelId,
    required int deckId,
    required String firstFieldValue,
  }) async {
    duplicateChecks.add((
      modelId: modelId,
      deckId: deckId,
      firstFieldValue: firstFieldValue,
    ));
    return deckId == 2;
  }

  @override
  void dispose() {}
}

class _TestConfigNotifier extends AnkidroidConfigNotifier {
  @override
  AnkidroidConfig build() => const AnkidroidConfig(
    modelId: 5,
    modelName: 'Basic',
    deckId: 1,
    deckName: 'Default',
    fieldMapping: {'Front': 'expression', 'Back': 'glossary'},
  );
}

void main() {
  const noteData = AnkiNoteData(
    expression: '食べる',
    reading: 'タベル',
    glossaries: '["to eat"]',
    dictionaryName: 'JMdict',
  );

  late _FakeAnkidroidService fakeService;
  late AppDatabase db;

  setUp(() => db = createTestDatabase());
  tearDown(() async => db.close());

  Future<void> pumpScreen(WidgetTester tester, {String? saveSource}) async {
    fakeService = _FakeAnkidroidService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ankidroidServiceProvider.overrideWithValue(fakeService),
          ankidroidConfigProvider.overrideWith(_TestConfigNotifier.new),
          // The screen's stats write resolves statsRepositoryProvider, which
          // builds on databaseProvider.
          databaseProvider.overrideWithValue(db),
        ],
        child: buildLocalizedTestApp(
          home: saveSource == null
              ? const AnkiCardCreationScreen(noteData: noteData)
              : AnkiCardCreationScreen(
                  noteData: noteData,
                  saveSource: saveSource,
                ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> switchDeck(WidgetTester tester, String deckName) async {
    await tester.tap(find.text('Deck'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(deckName).last);
    await tester.pumpAndSettle();
  }

  testWidgets('no duplicate banner for a deck without the note', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.textContaining('Already in'), findsNothing);
    // The check ran against the configured deck with the first field value.
    expect(fakeService.duplicateChecks, isNotEmpty);
    expect(fakeService.duplicateChecks.first.deckId, 1);
    expect(fakeService.duplicateChecks.first.firstFieldValue, '食べる');
  });

  testWidgets('switching to a deck with the note shows a warning, '
      'send stays enabled', (tester) async {
    await pumpScreen(tester);

    await switchDeck(tester, 'Mining');

    expect(find.textContaining('Already in'), findsOneWidget);
    expect(find.textContaining('Mining'), findsWidgets);

    final sendButton = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(sendButton.onPressed, isNotNull);
  });

  testWidgets('switching back to a clean deck hides the warning', (
    tester,
  ) async {
    await pumpScreen(tester);

    await switchDeck(tester, 'Mining');
    expect(find.textContaining('Already in'), findsOneWidget);

    await switchDeck(tester, 'Default');
    expect(find.textContaining('Already in'), findsNothing);
  });

  testWidgets('sending a card records a word event with the reader source', (
    tester,
  ) async {
    await pumpScreen(tester, saveSource: 'epub');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    final event = (await db.select(db.wordEvents).get()).single;
    expect(event.kind, 'anki');
    expect(event.expression, '食べる');
    expect(event.source, 'epub');
  });

  testWidgets('sending a card outside a reader records source other', (
    tester,
  ) async {
    await pumpScreen(tester);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    final event = (await db.select(db.wordEvents).get()).single;
    expect(event.source, 'other');
  });
}
