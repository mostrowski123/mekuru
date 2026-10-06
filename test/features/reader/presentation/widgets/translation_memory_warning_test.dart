import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/platform/device_memory.dart';
import 'package:mekuru/features/reader/presentation/widgets/translation_memory_warning.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../test_app.dart';

void main() {
  late ProviderContainer container;
  bool? result;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    result = null;
  });
  tearDown(() => debugDeviceLowOnMemory = null);

  Future<void> ask(WidgetTester tester, {required bool lowOnMemory}) async {
    debugDeviceLowOnMemory = lowOnMemory;
    container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: buildLocalizedTestApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async =>
                    result = await confirmTranslationMemory(context),
                child: const Text('ask'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ask'));
    await tester.pumpAndSettle();
  }

  testWidgets('a phone with enough memory goes ahead without asking', (
    tester,
  ) async {
    await ask(tester, lowOnMemory: false);

    expect(find.byType(AlertDialog), findsNothing);
    expect(result, isTrue);
  });

  testWidgets('a phone low on memory can continue', (tester) async {
    await ask(tester, lowOnMemory: true);
    expect(find.text('This phone may struggle'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
    expect(
      container.read(sentenceTranslationModeProvider),
      SentenceTranslationMode.shown,
    );
  });

  testWidgets('a phone low on memory can turn translation off', (tester) async {
    await ask(tester, lowOnMemory: true);

    await tester.tap(find.text('Turn off'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
    expect(
      container.read(sentenceTranslationModeProvider),
      SentenceTranslationMode.off,
    );
  });
}
