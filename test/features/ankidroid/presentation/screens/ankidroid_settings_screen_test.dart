import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/ankidroid/data/models/ankidroid_config.dart';
import 'package:mekuru/features/ankidroid/presentation/providers/ankidroid_providers.dart';
import 'package:mekuru/features/ankidroid/presentation/screens/ankidroid_settings_screen.dart';

import '../../../../test_app.dart';
import '../../ankidroid_test_doubles.dart';

void main() {
  const configWithStaleField = AnkidroidConfig(
    modelId: 5,
    modelName: 'Basic',
    deckId: 1,
    deckName: 'Default',
    fieldMapping: {'Front': 'expression', 'Word': 'reading'},
  );

  late FakeAnkidroidService fakeService;

  Future<void> pumpScreen(
    WidgetTester tester, {
    required AnkidroidConfig config,
    void Function(FakeAnkidroidService service)? setUpService,
  }) async {
    fakeService = FakeAnkidroidService()
      // The configured note type kept "Word" but lost "Front".
      ..fieldList = ['Word', 'Meaning']
      ..deckList = {1: 'Default'};
    setUpService?.call(fakeService);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ankidroidServiceProvider.overrideWithValue(fakeService),
          ankidroidConfigProvider.overrideWith(
            () => TestAnkidroidConfigNotifier(config),
          ),
        ],
        child: buildLocalizedTestApp(home: const AnkidroidSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Map<String, String> currentMapping(WidgetTester tester) {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AnkidroidSettingsScreen)),
    );
    return container.read(ankidroidConfigProvider).fieldMapping;
  }

  testWidgets('flags a note type that no longer exists in Anki', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      config: configWithStaleField,
      setUpService: (s) => s.fieldList = [],
    );

    expect(
      find.textContaining('Basic — no longer exists in Anki'),
      findsOneWidget,
    );
  });

  testWidgets('flags a deck that no longer exists in Anki', (tester) async {
    await pumpScreen(
      tester,
      config: configWithStaleField,
      setUpService: (s) => s.deckList = {9: 'Other'},
    );

    expect(
      find.textContaining('Default — no longer exists in Anki'),
      findsOneWidget,
    );
  });

  testWidgets('a failed read shows the connect error, not a deletion claim', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      config: configWithStaleField,
      setUpService: (s) => s.fieldList = null,
    );

    expect(find.textContaining('Could not connect'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('no longer exists'), findsNothing);
  });

  testWidgets('lists a stale mapped field with its data source', (
    tester,
  ) async {
    await pumpScreen(tester, config: configWithStaleField);

    expect(find.text('Front'), findsOneWidget);
    expect(find.textContaining('mapped to Expression'), findsOneWidget);
  });

  testWidgets('removing a stale mapping drops it from the config', (
    tester,
  ) async {
    await pumpScreen(tester, config: configWithStaleField);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.text('Front'), findsNothing);
    expect(currentMapping(tester), {'Word': 'reading'});
  });

  testWidgets('re-assigning a stale mapping moves its data source to an '
      'existing field', (tester) async {
    await pumpScreen(tester, config: configWithStaleField);

    await tester.tap(find.text('Front'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Move "Expression" to'), findsOneWidget);

    await tester.tap(find.text('Meaning').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('no longer exists'), findsNothing);
    expect(currentMapping(tester), {
      'Word': 'reading',
      'Meaning': 'expression',
    });
  });

  testWidgets('a failed field query while picking a note type keeps the '
      'previous selection and mapping', (tester) async {
    await pumpScreen(tester, config: configWithStaleField);

    // The field query starts failing after the screen loaded.
    fakeService.fieldList = null;
    await tester.tap(find.text('Anki Note Type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Basic').last);
    await tester.pumpAndSettle();

    final config = ProviderScope.containerOf(
      tester.element(find.byType(AnkidroidSettingsScreen)),
    ).read(ankidroidConfigProvider);
    expect(config.fieldMapping, configWithStaleField.fieldMapping);
    expect(config.modelName, 'Basic');
  });
}
