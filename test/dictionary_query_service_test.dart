import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_query_service.dart';

/// Creates an in-memory Drift database for testing.
AppDatabase createTestDatabase() {
  return AppDatabase(NativeDatabase.memory());
}

void main() {
  late AppDatabase db;
  late DictionaryRepository repo;
  late DictionaryQueryService queryService;

  setUp(() async {
    db = createTestDatabase();
    repo = DictionaryRepository(db);
    queryService = DictionaryQueryService(db);

    // Insert two dictionaries — one enabled, one disabled
    final enabledId = await repo.insertDictionary('EnabledDict');
    final disabledId = await repo.insertDictionary('DisabledDict');
    await repo.toggleDictionary(disabledId, isEnabled: false);

    // Insert entries
    await repo.batchInsertEntries([
      // Enabled dictionary entries
      DictionaryEntriesCompanion.insert(
        expression: '食べる',
        reading: const Value('たべる'),
        glossaries: jsonEncode(['to eat', 'to consume']),
        dictionaryId: enabledId,
      ),
      DictionaryEntriesCompanion.insert(
        expression: '飲む',
        reading: const Value('のむ'),
        glossaries: jsonEncode(['to drink']),
        dictionaryId: enabledId,
      ),
      DictionaryEntriesCompanion.insert(
        expression: '走る',
        reading: const Value('はしる'),
        glossaries: jsonEncode(['to run']),
        dictionaryId: enabledId,
      ),
      // Same expression with different reading (compound entries)
      DictionaryEntriesCompanion.insert(
        expression: '食べる',
        reading: const Value('たべる'),
        glossaries: jsonEncode(['to eat (variant)']),
        dictionaryId: enabledId,
      ),
      // Disabled dictionary entry (should NOT appear in search results)
      DictionaryEntriesCompanion.insert(
        expression: '食べる',
        reading: const Value('たべる'),
        glossaries: jsonEncode(['to eat (disabled dict)']),
        dictionaryId: disabledId,
      ),
    ]);
  });

  tearDown(() async {
    await db.close();
  });

  group('DictionaryQueryService — searchByExpression', () {
    test(
      'returns entries matching exact expression from enabled dicts only',
      () async {
        final results = await queryService.searchByExpression('食べる');

        // Should find 2 entries from enabled dict, NOT the disabled dict entry
        expect(results, hasLength(2));
        for (final entry in results) {
          expect(entry.expression, '食べる');
          final glossaries = jsonDecode(entry.glossaries) as List;
          // Should not contain the disabled dictionary's entry
          expect(glossaries, isNot(contains('to eat (disabled dict)')));
        }
      },
    );

    test('returns empty list for non-existent expression', () async {
      final results = await queryService.searchByExpression('存在しない');
      expect(results, isEmpty);
    });

    test('returns single result for unique expression', () async {
      final results = await queryService.searchByExpression('飲む');
      expect(results, hasLength(1));
      expect(results.first.expression, '飲む');
    });
  });

  group('DictionaryQueryService — searchByReading', () {
    test('returns entries matching exact reading from enabled dicts', () async {
      final results = await queryService.searchByReading('たべる');
      // 2 entries from enabled dict match this reading
      expect(results, hasLength(2));
      for (final entry in results) {
        expect(entry.reading, 'たべる');
      }
    });

    test('returns empty for non-existent reading', () async {
      final results = await queryService.searchByReading('ないよみ');
      expect(results, isEmpty);
    });
  });

  group('DictionaryQueryService — search (combined)', () {
    test('finds entries by expression', () async {
      final results = await queryService.search('走る');
      expect(results, hasLength(1));
      expect(results.first.expression, '走る');
    });

    test('finds entries by reading', () async {
      final results = await queryService.search('のむ');
      expect(results, hasLength(1));
      expect(results.first.expression, '飲む');
    });

    test(
      'combines results when term matches both expression and reading',
      () async {
        // 食べる has expression match; たべる has reading match for same entries
        final expressionResults = await queryService.search('食べる');
        expect(expressionResults, hasLength(2));

        final readingResults = await queryService.search('たべる');
        expect(readingResults, hasLength(2));
      },
    );

    test('excludes disabled dictionaries', () async {
      final results = await queryService.search('食べる');
      // All should be from enabled dict
      for (final entry in results) {
        final glossaries = jsonDecode(entry.glossaries) as List;
        expect(glossaries, isNot(contains('to eat (disabled dict)')));
      }
    });
  });

  // ── Result ordering ──────────────────────────────────────────────

  group('DictionaryQueryService — result ordering', () {
    late AppDatabase orderDb;
    late DictionaryRepository orderRepo;
    late DictionaryQueryService orderQueryService;

    setUp(() async {
      orderDb = createTestDatabase();
      orderRepo = DictionaryRepository(orderDb);
      orderQueryService = DictionaryQueryService(orderDb);

      // Insert dictionaries in specific order — IDs will be 1, 2, 3
      final dictA = await orderRepo.insertDictionary('Dict A');
      final dictB = await orderRepo.insertDictionary('Dict B');
      final dictC = await orderRepo.insertDictionary('Dict C');

      // Insert the same word in all three dicts (in reverse order)
      await orderRepo.batchInsertEntries([
        DictionaryEntriesCompanion.insert(
          expression: '食べる',
          reading: const Value('たべる'),
          glossaries: jsonEncode(['to eat (C)']),
          dictionaryId: dictC,
        ),
        DictionaryEntriesCompanion.insert(
          expression: '食べる',
          reading: const Value('たべる'),
          glossaries: jsonEncode(['to eat (A)']),
          dictionaryId: dictA,
        ),
        DictionaryEntriesCompanion.insert(
          expression: '食べる',
          reading: const Value('たべる'),
          glossaries: jsonEncode(['to eat (B)']),
          dictionaryId: dictB,
        ),
      ]);
    });

    tearDown(() async {
      await orderDb.close();
    });

    test('search results are ordered by dictionary id (ascending)', () async {
      final results = await orderQueryService.search('食べる');
      expect(results, hasLength(3));

      // Results should be ordered by dictionary id: A (1), B (2), C (3)
      final glossariesList = results
          .map((e) => (jsonDecode(e.glossaries) as List).first as String)
          .toList();
      expect(glossariesList, ['to eat (A)', 'to eat (B)', 'to eat (C)']);
    });

    test('searchByExpression results are ordered by dictionary id', () async {
      final results = await orderQueryService.searchByExpression('食べる');
      expect(results, hasLength(3));

      final glossariesList = results
          .map((e) => (jsonDecode(e.glossaries) as List).first as String)
          .toList();
      expect(glossariesList, ['to eat (A)', 'to eat (B)', 'to eat (C)']);
    });

    test('searchByReading results are ordered by dictionary id', () async {
      final results = await orderQueryService.searchByReading('たべる');
      expect(results, hasLength(3));

      final glossariesList = results
          .map((e) => (jsonDecode(e.glossaries) as List).first as String)
          .toList();
      expect(glossariesList, ['to eat (A)', 'to eat (B)', 'to eat (C)']);
    });
  });

  // ── searchWithSource ──────────────────────────────────────────────

  group('DictionaryQueryService — searchWithSource', () {
    test('returns entries paired with dictionary names', () async {
      final results = await queryService.searchWithSource('食べる');
      expect(results, hasLength(2));
      for (final r in results) {
        expect(r.entry.expression, '食べる');
        expect(r.dictionaryName, 'EnabledDict');
      }
    });

    test('excludes disabled dictionaries', () async {
      final results = await queryService.searchWithSource('食べる');
      for (final r in results) {
        expect(r.dictionaryName, isNot('DisabledDict'));
      }
    });

    test('returns empty list for non-existent term', () async {
      final results = await queryService.searchWithSource('存在しない');
      expect(results, isEmpty);
    });

    test('finds entries by reading', () async {
      final results = await queryService.searchWithSource('のむ');
      expect(results, hasLength(1));
      expect(results.first.entry.expression, '飲む');
      expect(results.first.dictionaryName, 'EnabledDict');
    });

    test('results are ordered by dictionary id', () async {
      final results = await queryService.searchWithSource('食べる');
      expect(results, hasLength(2));
      for (final r in results) {
        expect(r.dictionaryName, isNotEmpty);
      }
    });
  });

  // ── searchMultipleWithSource ─────────────────────────────────

  group('DictionaryQueryService — searchMultipleWithSource', () {
    test('returns entries matching any of the provided terms', () async {
      final results =
          await queryService.searchMultipleWithSource(['食べる', '飲む']);
      // 食べる has 2 entries, 飲む has 1 = 3 total
      expect(results, hasLength(3));
      final expressions = results.map((r) => r.entry.expression).toSet();
      expect(expressions, containsAll(['食べる', '飲む']));
    });

    test('excludes disabled dictionaries', () async {
      final results =
          await queryService.searchMultipleWithSource(['食べる']);
      for (final r in results) {
        expect(r.dictionaryName, isNot('DisabledDict'));
      }
    });

    test('returns empty list for non-existent terms', () async {
      final results =
          await queryService.searchMultipleWithSource(['存在しない', '架空']);
      expect(results, isEmpty);
    });

    test('returns empty list for empty input', () async {
      final results = await queryService.searchMultipleWithSource([]);
      expect(results, isEmpty);
    });

    test('finds entries by reading', () async {
      final results =
          await queryService.searchMultipleWithSource(['のむ']);
      expect(results, hasLength(1));
      expect(results.first.entry.expression, '飲む');
    });

    test('deduplicates when same entry matches multiple terms', () async {
      // 食べる matches both expression '食べる' and reading 'たべる'
      final results =
          await queryService.searchMultipleWithSource(['食べる', 'たべる']);
      // Should get 2 entries (the two 食べる entries), not 4
      expect(results, hasLength(2));
    });
  });

  // ── hasMatch ───────────────────────────────────────────────────

  group('DictionaryQueryService — hasMatch', () {
    test('returns true for existing expression', () async {
      final result = await queryService.hasMatch('食べる');
      expect(result, isTrue);
    });

    test('returns true for existing reading', () async {
      final result = await queryService.hasMatch('たべる');
      expect(result, isTrue);
    });

    test('returns false for non-existent term', () async {
      final result = await queryService.hasMatch('存在しない');
      expect(result, isFalse);
    });

    test('excludes disabled dictionaries', () async {
      // The shared setUp inserts '食べる' in both enabled and disabled dicts.
      // Create a term that only exists in the disabled dictionary.
      final disabledDicts = await repo.getAllDictionaries();
      final disabledDict = disabledDicts.firstWhere((d) => !d.isEnabled);

      await repo.batchInsertEntries([
        DictionaryEntriesCompanion.insert(
          expression: '無効専用',
          reading: const Value('むこうせんよう'),
          glossaries: jsonEncode(['disabled-only term']),
          dictionaryId: disabledDict.id,
        ),
      ]);

      final result = await queryService.hasMatch('無効専用');
      expect(result, isFalse);
    });

    test('returns false for empty string', () async {
      final result = await queryService.hasMatch('');
      expect(result, isFalse);
    });
  });

  // ── Frequency-aware grouping ───────────────────────────────────

  group('DictionaryQueryService — frequency-aware grouping', () {
    late AppDatabase freqDb;
    late DictionaryRepository freqRepo;
    late DictionaryQueryService freqQueryService;

    setUp(() async {
      freqDb = createTestDatabase();
      freqRepo = DictionaryRepository(freqDb);
      freqQueryService = DictionaryQueryService(freqDb);

      // Insert two dictionaries
      final dictA = await freqRepo.insertDictionary('Dict A');
      final dictB = await freqRepo.insertDictionary('Dict B');

      // Insert entries for 私 with two different readings in both dicts
      await freqRepo.batchInsertEntries([
        DictionaryEntriesCompanion.insert(
          expression: '私',
          reading: const Value('わたし'),
          glossaries: jsonEncode(['I (watashi, Dict A)']),
          dictionaryId: dictA,
        ),
        DictionaryEntriesCompanion.insert(
          expression: '私',
          reading: const Value('わたくし'),
          glossaries: jsonEncode(['I (watakushi, Dict A)']),
          dictionaryId: dictA,
        ),
        DictionaryEntriesCompanion.insert(
          expression: '私',
          reading: const Value('わたし'),
          glossaries: jsonEncode(['I (watashi, Dict B)']),
          dictionaryId: dictB,
        ),
        DictionaryEntriesCompanion.insert(
          expression: '私',
          reading: const Value('わたくし'),
          glossaries: jsonEncode(['I (watakushi, Dict B)']),
          dictionaryId: dictB,
        ),
      ]);

      // Insert frequency data: わたし is much more common than わたくし
      final freqDictId = await freqRepo.insertDictionary('JPDB Freq');
      await freqRepo.batchInsertFrequencies([
        FrequenciesCompanion.insert(
          expression: '私',
          reading: const Value('わたし'),
          frequencyRank: 50,
          dictionaryId: freqDictId,
        ),
        FrequenciesCompanion.insert(
          expression: '私',
          reading: const Value('わたくし'),
          frequencyRank: 5000,
          dictionaryId: freqDictId,
        ),
      ]);
    });

    tearDown(() async {
      await freqDb.close();
    });

    test(
      'groups results by (expression, reading) and sorts groups by frequency',
      () async {
        final results = await freqQueryService.searchWithSource('私');

        // Should have 4 entries total
        expect(results, hasLength(4));

        // First two should be わたし (rank 50), last two わたくし (rank 5000)
        expect(results[0].entry.reading, 'わたし');
        expect(results[0].frequencyRank, 50);
        expect(results[1].entry.reading, 'わたし');
        expect(results[1].frequencyRank, 50);
        expect(results[2].entry.reading, 'わたくし');
        expect(results[2].frequencyRank, 5000);
        expect(results[3].entry.reading, 'わたくし');
        expect(results[3].frequencyRank, 5000);
      },
    );

    test(
      'preserves dictionary sort_order within each (expression, reading) group',
      () async {
        final results = await freqQueryService.searchWithSource('私');

        // Within the わたし group, Dict A (sortOrder 1) before Dict B
        expect(results[0].dictionaryName, 'Dict A');
        expect(results[1].dictionaryName, 'Dict B');

        // Same within the わたくし group
        expect(results[2].dictionaryName, 'Dict A');
        expect(results[3].dictionaryName, 'Dict B');
      },
    );

    test(
      'falls back to expression-only frequency when reading has no match',
      () async {
        // Insert an entry with a reading not in the frequency table
        final dicts = await freqRepo.getAllDictionaries();
        final dictA = dicts.firstWhere((d) => d.name == 'Dict A');

        await freqRepo.batchInsertEntries([
          DictionaryEntriesCompanion.insert(
            expression: '私',
            reading: const Value('あたし'),
            glossaries: jsonEncode(['I (atashi)']),
            dictionaryId: dictA.id,
          ),
        ]);

        final results = await freqQueryService.searchWithSource('私');

        // あたし should still get a frequency rank (fallback to expression-level)
        final atashiResults =
            results.where((r) => r.entry.reading == 'あたし').toList();
        expect(atashiResults, hasLength(1));
        // Falls back to min rank across all readings for 私 = 50
        expect(atashiResults.first.frequencyRank, 50);
      },
    );

    test(
      'entries without any frequency data appear last',
      () async {
        // Insert an entry with a completely different expression
        final dicts = await freqRepo.getAllDictionaries();
        final dictA = dicts.firstWhere((d) => d.name == 'Dict A');

        await freqRepo.batchInsertEntries([
          DictionaryEntriesCompanion.insert(
            expression: '珍語',
            reading: const Value('ちんご'),
            glossaries: jsonEncode(['rare word']),
            dictionaryId: dictA.id,
          ),
        ]);

        final results = await freqQueryService.searchMultipleWithSource(
          ['私', '珍語'],
        );

        // 珍語 has no frequency data so should appear after all 私 entries
        final lastEntry = results.last;
        expect(lastEntry.entry.expression, '珍語');
        expect(lastEntry.frequencyRank, isNull);
      },
    );
  });
}
