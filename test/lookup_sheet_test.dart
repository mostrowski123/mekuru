import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/models/dictionary_entry.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_query_service.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/features/reader/presentation/widgets/lookup_sheet.dart';
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
  _FakeDictionaryQueryService(super.db, {required this.lookupResultsByTerm});

  final Map<String, List<DictionaryEntryWithSource>> lookupResultsByTerm;
  final List<String> pitchAccentQueries = [];

  @override
  Future<List<DictionaryEntryWithSource>> searchLookupWithSource(
    String primary, [
    String? secondary,
  ]) async {
    return lookupResultsByTerm[primary] ?? const [];
  }

  @override
  Future<List<PitchAccentResult>> searchPitchAccents(String term) async {
    pitchAccentQueries.add(term);
    return const [];
  }
}

void main() {
  testWidgets('renders part-of-speech labels in lookup sheet results', (
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
      lookupResultsByTerm: {
        '食べる': [
          DictionaryEntryWithSource(entry: entry, dictionaryName: 'JMdict'),
        ],
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          dictionaryQueryServiceProvider.overrideWithValue(service),
        ],
        child: buildLocalizedTestApp(
          home: const Scaffold(
            body: SizedBox.expand(child: LookupSheet(selectedText: '食べる')),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Ichidan verb'), findsOneWidget);
    expect(find.text('Transitive verb'), findsOneWidget);
  });

  testWidgets('refreshes pitch accents when the lookup term changes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final service = _FakeDictionaryQueryService(
      db,
      lookupResultsByTerm: {
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

    Future<void> pumpLookupSheet(String selectedText) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            dictionaryQueryServiceProvider.overrideWithValue(service),
          ],
          child: buildLocalizedTestApp(
            home: Scaffold(
              body: SizedBox.expand(
                child: LookupSheet(selectedText: selectedText),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
    }

    await pumpLookupSheet('食べる');
    expect(find.text('to eat'), findsOneWidget);
    expect(service.pitchAccentQueries, ['食べる']);

    await pumpLookupSheet('走る');
    expect(find.text('to eat'), findsNothing);
    expect(find.text('to run'), findsOneWidget);
    expect(service.pitchAccentQueries, ['食べる', '走る']);
  });
}
