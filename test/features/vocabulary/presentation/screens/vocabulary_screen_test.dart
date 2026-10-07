import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/vocabulary/presentation/providers/vocabulary_providers.dart';
import 'package:mekuru/features/vocabulary/presentation/screens/vocabulary_screen.dart';

import '../../../../test_app.dart';

Widget _app(List<SavedWord> words, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: [
        vocabularyListProvider.overrideWith((ref) => Stream.value(words)),
        ...overrides,
      ],
      child: buildLocalizedTestApp(home: const VocabularyScreen()),
    );

final _taberu = SavedWord(
  id: 7,
  expression: '食べる',
  reading: 'たべる',
  glossaries: '["to eat"]',
  sentenceContext: '',
  dateAdded: DateTime(2026, 10, 7),
);

/// Answers each CSV export with the next of [answers]: a saved path, null
/// (cancelled) or an error to throw.
Override _exportAnswering(List<Object?> answers, List<Set<int>?> calls) =>
    exportVocabularyProvider.overrideWith(
      (ref) => ({Set<int>? selectedIds}) async {
        calls.add({...?selectedIds});
        final answer = answers.removeAt(0);
        if (answer is Exception) throw answer;
        return answer as String?;
      },
    );

Future<void> _selectAndExport(WidgetTester tester) async {
  if (find.byType(Checkbox).evaluate().isEmpty) {
    await tester.tap(find.byTooltip('Export CSV'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byTooltip('Export selected'));
  await tester.pumpAndSettle();
}

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

  testWidgets('a saved CSV export confirms and leaves selection mode', (
    tester,
  ) async {
    final calls = <Set<int>?>[];
    await tester.pumpWidget(
      _app(
        [_taberu],
        overrides: [
          _exportAnswering([null, '/storage/vocabulary_export.csv'], calls),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // Cancelled in the save dialog: nothing to say, the selection stays.
    await _selectAndExport(tester);
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    await _selectAndExport(tester);
    expect(calls, [
      {7},
      {7},
    ]);
    expect(find.text('CSV exported'), findsOneWidget);
    expect(find.text('1 selected'), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
  });

  testWidgets('a failed CSV export says why and keeps the selection', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        [_taberu],
        overrides: [
          _exportAnswering([Exception('disk full')], []),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await _selectAndExport(tester);
    expect(find.text('Error: Exception: disk full'), findsOneWidget);
    expect(find.text('1 selected'), findsOneWidget);
  });
}
