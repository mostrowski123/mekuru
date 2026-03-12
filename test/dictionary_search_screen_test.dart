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
    required this.results,
  });

  final List<DictionaryEntryWithSource> results;
  final List<PitchAccentResult> pitchAccents = const [];

  @override
  Future<List<DictionaryEntryWithSource>> fuzzySearchWithSource(
    String term,
  ) async {
    return results;
  }

  @override
  Future<List<PitchAccentResult>> searchPitchAccents(String term) async {
    return pitchAccents;
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

    final entry = _buildEntry();
    final service = _FakeDictionaryQueryService(
      db,
      results: [
        DictionaryEntryWithSource(entry: entry, dictionaryName: 'JMdict'),
      ],
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
}
