import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/models/dictionary_entry.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_query_service.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/features/dictionary/presentation/screens/dictionary_search_screen.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/main.dart' show databaseProvider;

import '../test/test_app.dart';
import 'shared/test_infrastructure.dart';
import 'test_helpers.dart';

class _BenchmarkDictionaryQueryService extends DictionaryQueryService {
  _BenchmarkDictionaryQueryService(super.db, {required this.results});

  final List<DictionaryEntryWithSource> results;

  @override
  Future<List<DictionaryEntryWithSource>> fuzzySearchWithSource(
    String term,
  ) async {
    if (term == 'benchmark') {
      return results;
    }
    return const [];
  }

  @override
  Future<Map<String, List<PitchAccentResult>>> searchPitchAccentsBatch(
    Iterable<String> expressions,
  ) async {
    return {for (final expression in expressions) expression: const []};
  }
}

List<DictionaryEntryWithSource> _buildBenchmarkResults() {
  final results = <DictionaryEntryWithSource>[];
  var id = 1;

  for (var i = 0; i < 220; i++) {
    final expression = '単語$i';
    final reading = 'たんご$i';
    results.addAll([
      DictionaryEntryWithSource(
        entry: DictionaryEntry(
          id: id++,
          expression: expression,
          reading: reading,
          entryKind: DictionaryEntryKinds.regular,
          kanjiOnyomi: '',
          kanjiKunyomi: '',
          definitionTags: 'v1',
          rules: 'vt',
          termTags: 'P',
          glossaries: jsonEncode(['日本語 例文 補足 情報 語彙 説明', '関連 単語 表現 用法 注意']),
          dictionaryId: 1,
        ),
        dictionaryName: 'JMdict',
        frequencyRank: i + 1,
      ),
      DictionaryEntryWithSource(
        entry: DictionaryEntry(
          id: id++,
          expression: expression,
          reading: reading,
          entryKind: DictionaryEntryKinds.regular,
          kanjiOnyomi: '',
          kanjiKunyomi: '',
          definitionTags: 'adj-i',
          rules: '',
          termTags: '',
          glossaries: jsonEncode(['参考 日本語 追加 解説 用例', '慣用 表現 語感 使い方']),
          dictionaryId: 2,
        ),
        dictionaryName: 'Example Dictionary',
        frequencyRank: i + 1,
      ),
      DictionaryEntryWithSource(
        entry: DictionaryEntry(
          id: id++,
          expression: expression,
          reading: reading,
          entryKind: DictionaryEntryKinds.regular,
          kanjiOnyomi: '',
          kanjiKunyomi: '',
          definitionTags: '',
          rules: '',
          termTags: '',
          glossaries: jsonEncode(['補助 説明 日本語 単語 追加']),
          dictionaryId: 2,
        ),
        dictionaryName: 'Example Dictionary',
        frequencyRank: i + 1,
      ),
    ]);
  }

  return results;
}

Future<void> _runScrollLoops(
  WidgetTester tester,
  Finder scrollable, {
  int loops = 18,
}) async {
  for (var i = 0; i < loops; i++) {
    await tester.fling(scrollable, const Offset(0, -1600), 3500);
    await tester.pumpAndSettle();
    await tester.fling(scrollable, const Offset(0, 1600), 3500);
    await tester.pumpAndSettle();
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('dictionary search scroll benchmark', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final service = _BenchmarkDictionaryQueryService(
      db,
      results: _buildBenchmarkResults(),
    );
    final dictionaries = [
      DictionaryMeta(
        id: 1,
        name: 'JMdict',
        isEnabled: true,
        dateImported: DateTime(2026, 3, 13),
        sortOrder: 0,
        isHidden: false,
      ),
      DictionaryMeta(
        id: 2,
        name: 'Example Dictionary',
        isEnabled: true,
        dateImported: DateTime(2026, 3, 13),
        sortOrder: 1,
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
          appSettingsStorageProvider.overrideWithValue(
            InMemoryAppSettingsStorage(),
          ),
        ],
        child: buildLocalizedTestApp(
          home: const DictionarySearchScreen(initialQuery: 'benchmark'),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await pumpUntilVisible(
      tester,
      find.byType(ListView),
      timeout: const Duration(seconds: 30),
    );
    await tester.pumpAndSettle();

    final scrollable = find.byType(Scrollable).first;

    await _runScrollLoops(tester, scrollable, loops: 1);

    await binding.watchPerformance(() async {
      await _runScrollLoops(tester, scrollable);
    }, reportKey: 'dictionary_scroll');

    final summary = binding.reportData?['dictionary_scroll'];
    expect(summary, isNotNull);
    debugPrint('dictionary_scroll_benchmark ${jsonEncode(summary)}');
  });
}
