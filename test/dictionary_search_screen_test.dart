import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/features/dictionary/presentation/screens/dictionary_search_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('shows guidance when all imported dictionaries are disabled', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final dictionaries = [
      DictionaryMeta(
        id: 1,
        name: 'JMdict English',
        isEnabled: false,
        dateImported: DateTime(2026, 3, 8),
        sortOrder: 1,
        isHidden: false,
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dictionariesProvider.overrideWith(
            (ref) => Stream.value(dictionaries),
          ),
        ],
        child: const MaterialApp(home: DictionarySearchScreen()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Your dictionaries are turned off'), findsOneWidget);
    expect(find.text('Enable dictionaries'), findsOneWidget);
    expect(find.text('Starter pack'), findsOneWidget);
  });
}
