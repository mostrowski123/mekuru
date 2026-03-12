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

DictionaryEntry _buildEntry() {
  return DictionaryEntry(
    id: 1,
    expression: '食べる',
    reading: 'たべる',
    entryKind: DictionaryEntryKinds.regular,
    kanjiOnyomi: '',
    kanjiKunyomi: '',
    definitionTags: 'v1',
    rules: 'vt',
    termTags: 'P',
    glossaries: '["to eat"]',
    dictionaryId: 1,
  );
}

class _FakeDictionaryQueryService extends DictionaryQueryService {
  _FakeDictionaryQueryService(
    super.db, {
    required this.lookupResults,
    this.pitchAccents = const [],
  });

  final List<DictionaryEntryWithSource> lookupResults;
  final List<PitchAccentResult> pitchAccents;

  @override
  Future<List<DictionaryEntryWithSource>> searchLookupWithSource(
    String primary, [
    String? secondary,
  ]) async {
    return lookupResults;
  }

  @override
  Future<List<PitchAccentResult>> searchPitchAccents(String term) async {
    return pitchAccents;
  }
}

void main() {
  testWidgets('renders part-of-speech labels in lookup sheet results', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final entry = _buildEntry();
    final service = _FakeDictionaryQueryService(
      db,
      lookupResults: [
        DictionaryEntryWithSource(entry: entry, dictionaryName: 'JMdict'),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          dictionaryQueryServiceProvider.overrideWithValue(service),
        ],
        child: buildLocalizedTestApp(
          home: const Scaffold(
            body: SizedBox.expand(
              child: LookupSheet(selectedText: '食べる'),
            ),
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
}
