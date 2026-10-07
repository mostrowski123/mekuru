import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/vocabulary/presentation/providers/vocabulary_providers.dart';
import 'package:mekuru/features/vocabulary/presentation/screens/vocabulary_screen.dart';

import '../../../../test_app.dart';

Widget _app(List<SavedWord> words) => ProviderScope(
  overrides: [
    vocabularyListProvider.overrideWith((ref) => Stream.value(words)),
  ],
  child: buildLocalizedTestApp(home: const VocabularyScreen()),
);

void main() {
  testWidgets('a definition with a note and senses shows in full', (
    tester,
  ) async {
    // Jitendex's shape for 円柱: a bracketed note, then one line per sense.
    final word = SavedWord(
      id: 1,
      expression: '円柱',
      reading: 'えんちゅう',
      glossaries: jsonEncode([
        {
          'type': 'structured-content',
          'content': [
            '〔',
            {'tag': 'span', 'content': '円柱'},
            ' only〕',
            {'tag': 'div', 'content': 'column; cylinder'},
            {'tag': 'div', 'content': 'round pillar'},
          ],
        },
      ]),
      sentenceContext: '',
      dateAdded: DateTime(2026, 10, 7),
    );
    await tester.pumpWidget(_app([word]));
    await tester.pumpAndSettle();

    // The one-line preview, not just "〔".
    expect(
      find.text('えんちゅう - 〔円柱 only〕; column; cylinder; round pillar'),
      findsOneWidget,
    );

    await tester.tap(find.text('円柱'));
    await tester.pumpAndSettle();
    // Expanded: the whole definition, also when it is the only one.
    expect(
      find.text('〔円柱 only〕\ncolumn; cylinder\nround pillar'),
      findsOneWidget,
    );
  });
}
