import 'package:flutter/material.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/models/dictionary_entry.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_query_service.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/features/dictionary/presentation/screens/dictionary_search_screen.dart';
import 'package:mekuru/main.dart' show databaseProvider;
import 'package:shared_preferences/shared_preferences.dart';

import 'test_app.dart';

DictionaryEntry _buildEntry({
  required int id,
  required String expression,
  required String reading,
  required String glossaries,
}) {
  return DictionaryEntry(
    id: id,
    expression: expression,
    reading: reading,
    entryKind: DictionaryEntryKinds.regular,
    kanjiOnyomi: '',
    kanjiKunyomi: '',
    definitionTags: 'v1',
    rules: 'vt',
    termTags: 'P',
    glossaries: glossaries,
    dictionaryId: 1,
  );
}

class _FakeDictionaryQueryService extends DictionaryQueryService {
  _FakeDictionaryQueryService(super.db, {required this.resultsByTerm});

  final Map<String, List<DictionaryEntryWithSource>> resultsByTerm;
  final List<List<String>> pitchAccentBatchQueries = [];

  @override
  Future<List<DictionaryEntryWithSource>> fuzzySearchWithSource(
    String term,
  ) async {
    return resultsByTerm[term] ?? const [];
  }

  @override
  Future<List<PitchAccentResult>> searchPitchAccents(String term) async {
    return const [];
  }

  @override
  Future<Map<String, List<PitchAccentResult>>> searchPitchAccentsBatch(
    Iterable<String> expressions,
  ) async {
    final batch = expressions.toList(growable: false);
    pitchAccentBatchQueries.add(batch);
    return {for (final expression in batch) expression: const []};
  }
}

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
        child: buildLocalizedTestApp(home: const DictionarySearchScreen()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Your dictionaries are turned off'), findsOneWidget);
    expect(find.text('Enable dictionaries'), findsOneWidget);
    expect(find.text('Starter pack'), findsOneWidget);
  });

  testWidgets('renders part-of-speech labels in dictionary search results', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final entry = _buildEntry(
      id: 1,
      expression: '食べる',
      reading: 'たべる',
      glossaries: '["to eat"]',
    );
    final service = _FakeDictionaryQueryService(
      db,
      resultsByTerm: {
        '食べる': [
          DictionaryEntryWithSource(entry: entry, dictionaryName: 'JMdict'),
        ],
      },
    );

    final dictionaries = [
      DictionaryMeta(
        id: 1,
        name: 'JMdict',
        isEnabled: true,
        dateImported: DateTime(2026, 3, 12),
        sortOrder: 0,
        isHidden: false,
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          dictionaryQueryServiceProvider.overrideWithValue(service),
          dictionariesProvider.overrideWith(
            (ref) => Stream.value(dictionaries),
          ),
        ],
        child: buildLocalizedTestApp(
          home: const DictionarySearchScreen(initialQuery: '食べる'),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Ichidan verb'), findsOneWidget);
    expect(find.text('Transitive verb'), findsOneWidget);
  });

  testWidgets(
    'refetches batched pitch accents when the visible result changes',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final service = _FakeDictionaryQueryService(
        db,
        resultsByTerm: {
          '食べる': [
            DictionaryEntryWithSource(
              entry: _buildEntry(
                id: 1,
                expression: '食べる',
                reading: 'たべる',
                glossaries: '["to eat"]',
              ),
              dictionaryName: 'JMdict',
            ),
          ],
          '走る': [
            DictionaryEntryWithSource(
              entry: _buildEntry(
                id: 2,
                expression: '走る',
                reading: 'はしる',
                glossaries: '["to run"]',
              ),
              dictionaryName: 'JMdict',
            ),
          ],
        },
      );

      final dictionaries = [
        DictionaryMeta(
          id: 1,
          name: 'JMdict',
          isEnabled: true,
          dateImported: DateTime(2026, 3, 12),
          sortOrder: 0,
          isHidden: false,
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            dictionaryQueryServiceProvider.overrideWithValue(service),
            dictionariesProvider.overrideWith(
              (ref) => Stream.value(dictionaries),
            ),
          ],
          child: buildLocalizedTestApp(
            home: const DictionarySearchScreen(initialQuery: '食べる'),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('to eat'), findsOneWidget);
      expect(
        service.pitchAccentBatchQueries.any(
          (batch) => batch.length == 1 && batch.first == '食べる',
        ),
        isTrue,
      );

      await tester.enterText(find.byType(TextField), '走る');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('to eat'), findsNothing);
      expect(find.text('to run'), findsOneWidget);
      expect(
        service.pitchAccentBatchQueries.any(
          (batch) => batch.length == 1 && batch.first == '走る',
        ),
        isTrue,
      );
    },
  );
}
