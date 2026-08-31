import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/ankidroid/data/models/anki_note_data.dart';
import 'package:mekuru/features/ankidroid/data/models/ankidroid_config.dart';
import 'package:mekuru/features/ankidroid/presentation/providers/ankidroid_providers.dart';
import 'package:mekuru/features/ankidroid/presentation/screens/anki_card_creation_screen.dart';
import 'package:mekuru/main.dart';

import '../../../../shared/test_database.dart';
import '../../../../test_app.dart';
import '../../ankidroid_test_doubles.dart';

const _defaultConfig = AnkidroidConfig(
  modelId: 5,
  modelName: 'Basic',
  deckId: 1,
  deckName: 'Default',
  fieldMapping: {'Front': 'expression', 'Back': 'glossary'},
);

void main() {
  const noteData = AnkiNoteData(
    expression: '食べる',
    reading: 'タベル',
    glossaries: '["to eat"]',
    dictionaryName: 'JMdict',
  );

  late FakeAnkidroidService fakeService;
  late AppDatabase db;

  setUp(() => db = createTestDatabase());
  tearDown(() async => db.close());

  Future<void> pumpScreen(
    WidgetTester tester, {
    String? saveSource,
    AnkidroidConfig config = _defaultConfig,
    void Function(FakeAnkidroidService service)? setUpService,
  }) async {
    fakeService = FakeAnkidroidService();
    setUpService?.call(fakeService);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ankidroidServiceProvider.overrideWithValue(fakeService),
          ankidroidConfigProvider.overrideWith(
            () => TestAnkidroidConfigNotifier(config),
          ),
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

  testWidgets('shows an error with a settings button when the note type '
      'is gone from Anki', (tester) async {
    await pumpScreen(tester, setUpService: (s) => s.fieldList = []);

    expect(find.textContaining('note type no longer exists'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    // The label must make clear this opens Mekuru's own settings screen,
    // not the AnkiDroid app's settings.
    expect(
      find.widgetWithText(FilledButton, "Mekuru's AnkiDroid Settings"),
      findsOneWidget,
    );
  });

  testWidgets('a failed field query shows the connect error, not a '
      'deletion claim', (tester) async {
    await pumpScreen(tester, setUpService: (s) => s.fieldList = null);

    expect(find.textContaining('Could not connect'), findsOneWidget);
    expect(find.textContaining('no longer exists'), findsNothing);
  });

  testWidgets('a failed deck query shows the connect error', (tester) async {
    await pumpScreen(tester, setUpService: (s) => s.deckList = null);

    expect(find.textContaining('Could not connect'), findsOneWidget);
    expect(find.textContaining('no longer exists'), findsNothing);
  });

  testWidgets('clears a deck that is gone from Anki and disables send', (
    tester,
  ) async {
    // Configured deck 1 no longer exists in AnkiDroid.
    await pumpScreen(tester, setUpService: (s) => s.deckList = {2: 'Mining'});

    expect(find.text('Not selected'), findsOneWidget);
    final sendButton = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(sendButton.onPressed, isNull);
  });

  testWidgets('shows a fix-mapping banner when a mapped field is gone '
      'from Anki', (tester) async {
    await pumpScreen(
      tester,
      config: const AnkidroidConfig(
        modelId: 5,
        modelName: 'Basic',
        deckId: 1,
        deckName: 'Default',
        fieldMapping: {
          'Front': 'expression',
          'Back': 'glossary',
          'Old': 'reading',
        },
      ),
    );

    expect(find.textContaining('no longer exist'), findsOneWidget);
    expect(find.textContaining('Old'), findsOneWidget);
    // The banner warns; it must not block sending.
    final sendButton = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(sendButton.onPressed, isNotNull);
  });

  testWidgets('failed send surfaces the error and reports the real cause', (
    tester,
  ) async {
    final warnings = <String>[];
    final failureParams = <Map<String, Object>?>[];
    usageLogSinkOverride = (message, attributes, {required isWarning}) {
      if (isWarning) warnings.add(message);
    };
    usageAnalyticsSinkOverride = (name, params) {
      if (name == 'anki_card_sent') failureParams.add(params);
    };
    addTearDown(() {
      usageLogSinkOverride = null;
      usageAnalyticsSinkOverride = null;
    });

    await pumpScreen(
      tester,
      setUpService: (s) => s.addNoteError = PlatformException(
        code: 'saf_io_error',
        message: 'model missing',
      ),
    );
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.textContaining('Failed to add note'), findsWidgets);
    expect(warnings, ['anki.card_sent']);
    expect(failureParams.single?['error_type'], 'PlatformException');
  });

  testWidgets('a rejected insert without an error still shows the failure '
      'and reports the fallback cause', (tester) async {
    final failureParams = <Map<String, Object>?>[];
    usageAnalyticsSinkOverride = (name, params) {
      if (name == 'anki_card_sent') failureParams.add(params);
    };
    addTearDown(() => usageAnalyticsSinkOverride = null);

    await pumpScreen(tester, setUpService: (s) => s.addNoteResult = null);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.textContaining('Failed to add note'), findsWidgets);
    expect(failureParams.single?['error_type'], 'StateError');
  });

  testWidgets('tapping the fix-mapping banner opens Mekuru\'s AnkiDroid '
      'settings', (tester) async {
    await pumpScreen(
      tester,
      config: const AnkidroidConfig(
        modelId: 5,
        modelName: 'Basic',
        deckId: 1,
        deckName: 'Default',
        fieldMapping: {'Front': 'expression', 'Old': 'reading'},
      ),
    );

    await tester.tap(find.textContaining('no longer exist'));
    await tester.pumpAndSettle();

    // The settings screen opened and shows the same stale field for repair.
    expect(find.text('AnkiDroid Integration'), findsOneWidget);
    expect(find.textContaining('mapped to Reading'), findsOneWidget);
  });
}
