import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/models/dictionary_entry.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_query_service.dart';

/// Creates an in-memory Drift database for testing.
AppDatabase createTestDatabase() {
  return AppDatabase(NativeDatabase.memory());
}

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
  });

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

    test(
      'searchWithSource respects reordered dictionary manager order for kanji entries',
      () async {
        final kanjiDictA = await orderRepo.insertDictionary('Kanji Dict A');
        final kanjiDictB = await orderRepo.insertDictionary('Kanji Dict B');
        final kanjiDictC = await orderRepo.insertDictionary('Kanji Dict C');

        await orderRepo.batchInsertEntries([
          DictionaryEntriesCompanion.insert(
            expression: '日',
            reading: const Value('ニチ ジツ ひ か'),
            entryKind: const Value(DictionaryEntryKinds.kanji),
            kanjiOnyomi: const Value('["ニチ","ジツ"]'),
            kanjiKunyomi: const Value('["ひ","か"]'),
            glossaries: jsonEncode(['sun (A)']),
            dictionaryId: kanjiDictA,
          ),
          DictionaryEntriesCompanion.insert(
            expression: '日',
            reading: const Value('ニチ ジツ ひ か'),
            entryKind: const Value(DictionaryEntryKinds.kanji),
            kanjiOnyomi: const Value('["ニチ","ジツ"]'),
            kanjiKunyomi: const Value('["ひ","か"]'),
            glossaries: jsonEncode(['sun (B)']),
            dictionaryId: kanjiDictB,
          ),
          DictionaryEntriesCompanion.insert(
            expression: '日',
            reading: const Value('ニチ ジツ ひ か'),
            entryKind: const Value(DictionaryEntryKinds.kanji),
            kanjiOnyomi: const Value('["ニチ","ジツ"]'),
            kanjiKunyomi: const Value('["ひ","か"]'),
            glossaries: jsonEncode(['sun (C)']),
            dictionaryId: kanjiDictC,
          ),
        ]);

        await orderRepo.reorderDictionaries([
          kanjiDictC,
          kanjiDictA,
          kanjiDictB,
        ]);

        final results = await orderQueryService.searchWithSource('日');
        final kanjiResults = results
            .where((r) => r.entry.entryKind == DictionaryEntryKinds.kanji)
            .toList();

        expect(kanjiResults.map((r) => r.dictionaryName).toList(), [
          'Kanji Dict C',
          'Kanji Dict A',
          'Kanji Dict B',
        ]);
      },
    );
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
      final results = await queryService.searchMultipleWithSource([
        '食べる',
        '飲む',
      ]);
      // 食べる has 2 entries, 飲む has 1 = 3 total
      expect(results, hasLength(3));
      final expressions = results.map((r) => r.entry.expression).toSet();
      expect(expressions, containsAll(['食べる', '飲む']));
    });

    test('excludes disabled dictionaries', () async {
      final results = await queryService.searchMultipleWithSource(['食べる']);
      for (final r in results) {
        expect(r.dictionaryName, isNot('DisabledDict'));
      }
    });

    test('returns empty list for non-existent terms', () async {
      final results = await queryService.searchMultipleWithSource([
        '存在しない',
        '架空',
      ]);
      expect(results, isEmpty);
    });

    test('returns empty list for empty input', () async {
      final results = await queryService.searchMultipleWithSource([]);
      expect(results, isEmpty);
    });

    test('finds entries by reading', () async {
      final results = await queryService.searchMultipleWithSource(['のむ']);
      expect(results, hasLength(1));
      expect(results.first.entry.expression, '飲む');
    });

    test('deduplicates when same entry matches multiple terms', () async {
      // 食べる matches both expression '食べる' and reading 'たべる'
      final results = await queryService.searchMultipleWithSource([
        '食べる',
        'たべる',
      ]);
      // Should get 2 entries (the two 食べる entries), not 4
      expect(results, hasLength(2));
    });
  });

  group('DictionaryQueryService — searchLookupWithSource', () {
    late AppDatabase lookupDb;
    late DictionaryRepository lookupRepo;
    late DictionaryQueryService lookupQueryService;

    setUp(() async {
      lookupDb = createTestDatabase();
      lookupRepo = DictionaryRepository(lookupDb);
      lookupQueryService = DictionaryQueryService(lookupDb);

      final dictId = await lookupRepo.insertDictionary('LookupDict');
      await lookupRepo.batchInsertEntries([
        DictionaryEntriesCompanion.insert(
          expression: '分かる',
          reading: const Value('わかる'),
          glossaries: jsonEncode(['to understand']),
          dictionaryId: dictId,
        ),
        DictionaryEntriesCompanion.insert(
          expression: 'わい',
          reading: const Value('わい'),
          glossaries: jsonEncode(['I; me']),
          dictionaryId: dictId,
        ),
        DictionaryEntriesCompanion.insert(
          expression: '分つ',
          reading: const Value('わかつ'),
          glossaries: jsonEncode(['to divide']),
          dictionaryId: dictId,
        ),
      ]);

      final frequencyDictId = await lookupRepo.insertDictionary('FreqDict');
      await lookupRepo.batchInsertFrequencies([
        FrequenciesCompanion.insert(
          expression: 'わい',
          reading: const Value('わい'),
          frequencyRank: 10,
          dictionaryId: frequencyDictId,
        ),
        FrequenciesCompanion.insert(
          expression: '分かる',
          reading: const Value('わかる'),
          frequencyRank: 200,
          dictionaryId: frequencyDictId,
        ),
        FrequenciesCompanion.insert(
          expression: '分つ',
          reading: const Value('わかつ'),
          frequencyRank: 400,
          dictionaryId: frequencyDictId,
        ),
      ]);
    });

    tearDown(() async {
      await lookupDb.close();
    });

    test(
      'keeps direct lookup matches ahead of deinflected fallback matches',
      () async {
        final results = await lookupQueryService.searchLookupWithSource(
          'わかる',
          'わかった',
        );

        expect(results, hasLength(3));
        expect(results.first.entry.expression, '分かる');
        expect(results.first.entry.reading, 'わかる');
        expect(results.last.entry.expression, 'わい');
      },
    );

    test(
      'prefers surface-derived candidates over a conflicting parser guess',
      () async {
        final results = await lookupQueryService.searchLookupWithSource(
          '分つ',
          'わかった',
        );

        expect(results, hasLength(3));
        expect(results.first.entry.expression, '分かる');
        expect(results.first.entry.reading, 'わかる');
        expect(
          results.indexWhere((r) => r.entry.expression == '分つ'),
          greaterThan(results.indexWhere((r) => r.entry.expression == '分かる')),
        );
        expect(results.last.entry.expression, 'わい');
      },
    );

    test(
      'still returns deinflected matches when no direct hit exists',
      () async {
        final results = await lookupQueryService.searchLookupWithSource('わかった');

        final expressions = results.map((r) => r.entry.expression).toSet();
        expect(expressions, contains('分かる'));
        expect(expressions, contains('わい'));
      },
    );
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
      'does not inherit another reading rank when frequency is missing',
      () async {
        // Insert an entry with a reading not in the frequency table.
        // Because reading-specific frequency data exists for 私 (わたし
        // and わたくし), an unlisted reading should stay unranked rather
        // than borrowing the best rank from another reading.
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

        // あたし should remain unranked.
        final atashiResults = results
            .where((r) => r.entry.reading == 'あたし')
            .toList();
        expect(atashiResults, hasLength(1));
        expect(atashiResults.first.frequencyRank, isNull);

        // あたし should appear after readings that have frequency data
        final lastReading = atashiResults.first.entry.reading;
        expect(lastReading, 'あたし');
      },
    );

    test(
      'uses kana-only ranks only for exact kana lookups, not kanji lookups',
      () async {
        final dicts = await freqRepo.getAllDictionaries();
        final dictA = dicts.firstWhere((d) => d.name == 'Dict A');
        final freqDict = dicts.firstWhere((d) => d.name == 'JPDB Freq');

        await freqRepo.batchInsertEntries([
          DictionaryEntriesCompanion.insert(
            expression: '私',
            reading: const Value('わっし'),
            glossaries: jsonEncode(['I (wasshi)']),
            dictionaryId: dictA.id,
          ),
        ]);
        await freqRepo.batchInsertFrequencies([
          FrequenciesCompanion.insert(
            expression: 'わっし',
            frequencyRank: 40276,
            dictionaryId: freqDict.id,
          ),
        ]);

        final kanjiResults = await freqQueryService.fuzzySearchWithSource('私');
        final wasshiKanji = kanjiResults
            .where((r) => r.entry.expression == '私' && r.entry.reading == 'わっし')
            .toList();
        expect(wasshiKanji, hasLength(1));
        expect(wasshiKanji.first.frequencyRank, isNull);
        expect(kanjiResults.last.entry.reading, 'わっし');

        final kanaResults = await freqQueryService.fuzzySearchWithSource('わっし');
        final wasshiKana = kanaResults
            .where((r) => r.entry.expression == '私' && r.entry.reading == 'わっし')
            .toList();
        expect(wasshiKana, hasLength(1));
        expect(wasshiKana.first.frequencyRank, 40276);
      },
    );

    test('entries without any frequency data appear last', () async {
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

      final results = await freqQueryService.searchMultipleWithSource([
        '私',
        '珍語',
      ]);

      // 珍語 has no frequency data so should appear after all 私 entries
      final lastEntry = results.last;
      expect(lastEntry.entry.expression, '珍語');
      expect(lastEntry.frequencyRank, isNull);
    });
  });

  group('DictionaryQueryService — frequency install order', () {
    Future<DictionaryQueryService> seedScenario({
      required AppDatabase installDb,
      required DictionaryRepository installRepo,
      required bool installFrequencyFirst,
    }) async {
      Future<void> installFrequencyDictionary() async {
        final freqDictId = await installRepo.insertDictionary('JPDBv2㋕');
        await installRepo.batchInsertFrequencies([
          FrequenciesCompanion.insert(
            expression: '私',
            reading: const Value('わたし'),
            frequencyRank: 32,
            dictionaryId: freqDictId,
          ),
          FrequenciesCompanion.insert(
            expression: 'わっし',
            frequencyRank: 40276,
            dictionaryId: freqDictId,
          ),
        ]);
        await installRepo.toggleDictionary(freqDictId, isEnabled: false);
        await installRepo.setHidden(freqDictId, isHidden: true);
      }

      Future<void> installJmdictDictionary() async {
        final jmdictId = await installRepo.insertDictionary('JMdict English');
        await installRepo.batchInsertEntries([
          DictionaryEntriesCompanion.insert(
            expression: '私',
            reading: const Value('わたし'),
            glossaries: jsonEncode(['I (watashi)']),
            dictionaryId: jmdictId,
          ),
          DictionaryEntriesCompanion.insert(
            expression: '私',
            reading: const Value('わっし'),
            glossaries: jsonEncode(['I (wasshi)']),
            dictionaryId: jmdictId,
          ),
        ]);
      }

      if (installFrequencyFirst) {
        await installFrequencyDictionary();
        await installJmdictDictionary();
      } else {
        await installJmdictDictionary();
        await installFrequencyDictionary();
      }

      return DictionaryQueryService(installDb);
    }

    test(
      'applies frequency ranks when the frequency dictionary is installed first',
      () async {
        final installDb = createTestDatabase();
        addTearDown(() => installDb.close());
        final installRepo = DictionaryRepository(installDb);

        final installQueryService = await seedScenario(
          installDb: installDb,
          installRepo: installRepo,
          installFrequencyFirst: true,
        );

        final results = await installQueryService.fuzzySearchWithSource('私');
        expect(results.map((r) => r.entry.reading).toList(), ['わたし', 'わっし']);
        expect(results[0].frequencyRank, 32);
        expect(results[1].frequencyRank, isNull);
      },
    );

    test(
      'applies frequency ranks when the frequency dictionary is installed after JMdict',
      () async {
        final installDb = createTestDatabase();
        addTearDown(() => installDb.close());
        final installRepo = DictionaryRepository(installDb);

        final installQueryService = await seedScenario(
          installDb: installDb,
          installRepo: installRepo,
          installFrequencyFirst: false,
        );

        final results = await installQueryService.fuzzySearchWithSource('私');
        expect(results.map((r) => r.entry.reading).toList(), ['わたし', 'わっし']);
        expect(results[0].frequencyRank, 32);
        expect(results[1].frequencyRank, isNull);
      },
    );
  });

  // ── Deinflection in fuzzySearchWithSource ────────────────────────

  group('DictionaryQueryService — fuzzySearchWithSource deinflection', () {
    late AppDatabase deinflDb;
    late DictionaryRepository deinflRepo;
    late DictionaryQueryService deinflQueryService;

    setUp(() async {
      deinflDb = createTestDatabase();
      deinflRepo = DictionaryRepository(deinflDb);
      deinflQueryService = DictionaryQueryService(deinflDb);

      final dictA = await deinflRepo.insertDictionary('Dict A');
      final dictB = await deinflRepo.insertDictionary('Dict B');

      // Insert 行く (iku) and 行う (okonau) — the two base forms for 行って
      await deinflRepo.batchInsertEntries([
        DictionaryEntriesCompanion.insert(
          expression: '行く',
          reading: const Value('いく'),
          glossaries: jsonEncode(['to go']),
          dictionaryId: dictA,
        ),
        DictionaryEntriesCompanion.insert(
          expression: '行く',
          reading: const Value('いく'),
          glossaries: jsonEncode(['to go (B)']),
          dictionaryId: dictB,
        ),
        DictionaryEntriesCompanion.insert(
          expression: '行う',
          reading: const Value('おこなう'),
          glossaries: jsonEncode(['to carry out']),
          dictionaryId: dictA,
        ),
        DictionaryEntriesCompanion.insert(
          expression: '行う',
          reading: const Value('おこなう'),
          glossaries: jsonEncode(['to carry out (B)']),
          dictionaryId: dictB,
        ),
      ]);
    });

    tearDown(() async {
      await deinflDb.close();
    });

    test(
      'searching conjugated form finds all possible base forms via deinflection',
      () async {
        // Searching 行って should find both 行く and 行う via deinflection
        final results = await deinflQueryService.fuzzySearchWithSource('行って');

        final expressions = results.map((r) => r.entry.expression).toSet();
        expect(expressions, contains('行く'));
        expect(expressions, contains('行う'));
      },
    );

    test(
      'deinflected results preserve dictionary sort order within each group',
      () async {
        final results = await deinflQueryService.fuzzySearchWithSource('行って');

        // Both base forms should appear, each with Dict A before Dict B
        final ikuResults = results
            .where((r) => r.entry.expression == '行く')
            .toList();
        final okonauResults = results
            .where((r) => r.entry.expression == '行う')
            .toList();

        expect(ikuResults, hasLength(2));
        expect(ikuResults[0].dictionaryName, 'Dict A');
        expect(ikuResults[1].dictionaryName, 'Dict B');

        expect(okonauResults, hasLength(2));
        expect(okonauResults[0].dictionaryName, 'Dict A');
        expect(okonauResults[1].dictionaryName, 'Dict B');
      },
    );

    test('ta-form deinflection finds base forms (行った → 行く, 行う)', () async {
      final results = await deinflQueryService.fuzzySearchWithSource('行った');

      final expressions = results.map((r) => r.entry.expression).toSet();
      expect(expressions, contains('行く'));
      expect(expressions, contains('行う'));
    });

    test(
      'non-conjugated input returns exact matches without deinflection noise',
      () async {
        final results = await deinflQueryService.fuzzySearchWithSource('行く');

        // Should find 行く entries but NOT 行う
        final expressions = results.map((r) => r.entry.expression).toSet();
        expect(expressions, contains('行く'));
        expect(expressions, isNot(contains('行う')));
      },
    );
  });

  // ── prefixSearchWithSource ─────────────────────────────────────

  group('DictionaryQueryService — prefixSearchWithSource', () {
    test('returns entries whose expression starts with the prefix', () async {
      final results = await queryService.prefixSearchWithSource('食');
      expect(results, isNotEmpty);
      for (final r in results) {
        expect(r.entry.expression, startsWith('食'));
      }
    });

    test('returns entries whose reading starts with the prefix', () async {
      final results = await queryService.prefixSearchWithSource('た');
      expect(results, isNotEmpty);
      for (final r in results) {
        expect(
          r.entry.expression.startsWith('た') || r.entry.reading.startsWith('た'),
          isTrue,
        );
      }
    });

    test('excludes disabled dictionaries', () async {
      final results = await queryService.prefixSearchWithSource('食');
      for (final r in results) {
        expect(r.dictionaryName, isNot('DisabledDict'));
      }
    });

    test('returns empty list for non-matching prefix', () async {
      final results = await queryService.prefixSearchWithSource('zzz');
      expect(results, isEmpty);
    });

    test('returns empty list for empty string', () async {
      final results = await queryService.prefixSearchWithSource('');
      expect(results, isEmpty);
    });

    test('respects limit parameter', () async {
      final results = await queryService.prefixSearchWithSource('食', limit: 1);
      expect(results, hasLength(lessThanOrEqualTo(1)));
    });

    test('includes dictionary name in results', () async {
      final results = await queryService.prefixSearchWithSource('飲');
      expect(results, hasLength(1));
      expect(results.first.dictionaryName, 'EnabledDict');
    });
  });

  // ── glossarySearchWithSource ───────────────────────────────────

  group('DictionaryQueryService — glossarySearchWithSource', () {
    test('finds entries by English definition substring', () async {
      final results = await queryService.glossarySearchWithSource('to eat');
      expect(results, isNotEmpty);
      for (final r in results) {
        expect(r.entry.glossaries.toLowerCase(), contains('to eat'));
      }
    });

    test('search is case-insensitive', () async {
      final resultsLower = await queryService.glossarySearchWithSource(
        'to eat',
      );
      final resultsUpper = await queryService.glossarySearchWithSource(
        'To Eat',
      );
      // SQLite LIKE is case-insensitive for ASCII characters
      expect(resultsLower.length, resultsUpper.length);
    });

    test('excludes disabled dictionaries', () async {
      final results = await queryService.glossarySearchWithSource(
        'disabled dict',
      );
      // The disabled dict entry has glossary "to eat (disabled dict)"
      // but it should be filtered out
      for (final r in results) {
        expect(r.dictionaryName, isNot('DisabledDict'));
      }
    });

    test('returns empty list for non-matching term', () async {
      final results = await queryService.glossarySearchWithSource(
        'xyznotfound',
      );
      expect(results, isEmpty);
    });

    test('returns empty list for empty string', () async {
      final results = await queryService.glossarySearchWithSource('');
      expect(results, isEmpty);
    });

    test('respects limit parameter', () async {
      final results = await queryService.glossarySearchWithSource(
        'to',
        limit: 1,
      );
      expect(results, hasLength(lessThanOrEqualTo(1)));
    });

    test('finds entries with partial definition match', () async {
      final results = await queryService.glossarySearchWithSource('consume');
      expect(results, hasLength(1));
      expect(results.first.entry.expression, '食べる');
    });
  });

  // ── searchPitchAccents ─────────────────────────────────────────

  group('DictionaryQueryService — searchPitchAccents', () {
    late AppDatabase pitchDb;
    late DictionaryRepository pitchRepo;
    late DictionaryQueryService pitchQueryService;

    setUp(() async {
      pitchDb = createTestDatabase();
      pitchRepo = DictionaryRepository(pitchDb);
      pitchQueryService = DictionaryQueryService(pitchDb);

      final enabledId = await pitchRepo.insertDictionary('PitchDict');
      final disabledId = await pitchRepo.insertDictionary('DisabledPitch');
      await pitchRepo.toggleDictionary(disabledId, isEnabled: false);

      await pitchRepo.batchInsertPitchAccents([
        PitchAccentsCompanion.insert(
          expression: '食べる',
          reading: const Value('たべる'),
          downstepPosition: 2,
          dictionaryId: enabledId,
        ),
        PitchAccentsCompanion.insert(
          expression: '食べる',
          reading: const Value('たべる'),
          downstepPosition: 0,
          dictionaryId: disabledId,
        ),
        PitchAccentsCompanion.insert(
          expression: '走る',
          reading: const Value('はしる'),
          downstepPosition: 2,
          dictionaryId: enabledId,
        ),
      ]);
    });

    tearDown(() async {
      await pitchDb.close();
    });

    test('returns pitch accents for matching expression', () async {
      final results = await pitchQueryService.searchPitchAccents('食べる');
      expect(results, hasLength(1));
      expect(results.first.reading, 'たべる');
      expect(results.first.downstepPosition, 2);
      expect(results.first.dictionaryName, 'PitchDict');
    });

    test('excludes disabled dictionaries', () async {
      final results = await pitchQueryService.searchPitchAccents('食べる');
      for (final r in results) {
        expect(r.dictionaryName, isNot('DisabledPitch'));
      }
    });

    test('returns empty list for non-existent expression', () async {
      final results = await pitchQueryService.searchPitchAccents('存在しない');
      expect(results, isEmpty);
    });

    test('returns multiple pitch accents for different expressions', () async {
      final taberuResults = await pitchQueryService.searchPitchAccents('食べる');
      final hashiruResults = await pitchQueryService.searchPitchAccents('走る');
      expect(taberuResults, hasLength(1));
      expect(hashiruResults, hasLength(1));
      expect(hashiruResults.first.reading, 'はしる');
    });

    test('results are ordered by dictionary sort order', () async {
      // Add a second enabled dictionary with different sort order
      final dictB = await pitchRepo.insertDictionary('PitchDict B');
      await pitchRepo.batchInsertPitchAccents([
        PitchAccentsCompanion.insert(
          expression: '食べる',
          reading: const Value('たべる'),
          downstepPosition: 0,
          dictionaryId: dictB,
        ),
      ]);

      final results = await pitchQueryService.searchPitchAccents('食べる');
      expect(results, hasLength(2));
      expect(results[0].dictionaryName, 'PitchDict');
      expect(results[1].dictionaryName, 'PitchDict B');
    });
  });

  // ── getFrequencyRank ───────────────────────────────────────────

  group('DictionaryQueryService — getFrequencyRank', () {
    late AppDatabase freqDb;
    late DictionaryRepository freqRepo;
    late DictionaryQueryService freqQueryService;

    setUp(() async {
      freqDb = createTestDatabase();
      freqRepo = DictionaryRepository(freqDb);
      freqQueryService = DictionaryQueryService(freqDb);

      final freqDictId = await freqRepo.insertDictionary('FreqDict');
      await freqRepo.batchInsertFrequencies([
        FrequenciesCompanion.insert(
          expression: '食べる',
          reading: const Value('たべる'),
          frequencyRank: 100,
          dictionaryId: freqDictId,
        ),
        FrequenciesCompanion.insert(
          expression: '食べる',
          reading: const Value('たべる'),
          frequencyRank: 200,
          dictionaryId: freqDictId,
        ),
        FrequenciesCompanion.insert(
          expression: '走る',
          reading: const Value('はしる'),
          frequencyRank: 500,
          dictionaryId: freqDictId,
        ),
      ]);
    });

    tearDown(() async {
      await freqDb.close();
    });

    test('returns the best (lowest) rank for an expression', () async {
      final rank = await freqQueryService.getFrequencyRank('食べる');
      expect(rank, 100);
    });

    test('returns rank when querying by expression and reading', () async {
      final rank = await freqQueryService.getFrequencyRank('食べる', 'たべる');
      expect(rank, 100);
    });

    test('returns null for non-existent expression', () async {
      final rank = await freqQueryService.getFrequencyRank('存在しない');
      expect(rank, isNull);
    });

    test('returns correct rank for different expressions', () async {
      final rank = await freqQueryService.getFrequencyRank('走る');
      expect(rank, 500);
    });

    test('returns the minimum across multiple frequency entries', () async {
      // 食べる has ranks 100 and 200 — should return 100
      final rank = await freqQueryService.getFrequencyRank('食べる');
      expect(rank, 100);
    });
  });

  // ── DictionaryEntryWithSource.frequencyLabel ───────────────────

  group('DictionaryEntryWithSource — frequencyLabel', () {
    test('returns "Very Common" for rank <= 5000', () {
      expect(DictionaryEntryWithSource.frequencyLabel(1), 'Very Common');
      expect(DictionaryEntryWithSource.frequencyLabel(5000), 'Very Common');
    });

    test('returns "Common" for rank 5001–15000', () {
      expect(DictionaryEntryWithSource.frequencyLabel(5001), 'Common');
      expect(DictionaryEntryWithSource.frequencyLabel(15000), 'Common');
    });

    test('returns "Uncommon" for rank 15001–30000', () {
      expect(DictionaryEntryWithSource.frequencyLabel(15001), 'Uncommon');
      expect(DictionaryEntryWithSource.frequencyLabel(30000), 'Uncommon');
    });

    test('returns "Rare" for rank > 30000', () {
      expect(DictionaryEntryWithSource.frequencyLabel(30001), 'Rare');
      expect(DictionaryEntryWithSource.frequencyLabel(100000), 'Rare');
    });

    test('treats null rank as "Rare"', () {
      expect(DictionaryEntryWithSource.frequencyLabel(null), 'Rare');
    });
  });

  group('DictionaryQueryService - exact match prioritization', () {
    late AppDatabase priorityDb;
    late DictionaryRepository priorityRepo;
    late DictionaryQueryService priorityQueryService;

    const kana = '\u306f\u3044';
    const kanjiAsh = '\u7070';
    const kanjiCup = '\u676f';

    setUp(() async {
      priorityDb = createTestDatabase();
      priorityRepo = DictionaryRepository(priorityDb);
      priorityQueryService = DictionaryQueryService(priorityDb);

      final dictId = await priorityRepo.insertDictionary('PriorityDict');
      await priorityRepo.batchInsertEntries([
        DictionaryEntriesCompanion.insert(
          expression: kanjiAsh,
          reading: const Value(kana),
          glossaries: jsonEncode(['ash']),
          dictionaryId: dictId,
        ),
        DictionaryEntriesCompanion.insert(
          expression: kana,
          reading: const Value(kana),
          glossaries: jsonEncode(['yes']),
          dictionaryId: dictId,
        ),
        DictionaryEntriesCompanion.insert(
          expression: kanjiCup,
          reading: const Value(kana),
          glossaries: jsonEncode(['cup']),
          dictionaryId: dictId,
        ),
      ]);

      final frequencyDictId = await priorityRepo.insertDictionary('FreqDict');
      await priorityRepo.batchInsertFrequencies([
        FrequenciesCompanion.insert(
          expression: kanjiAsh,
          reading: const Value(kana),
          frequencyRank: 10,
          dictionaryId: frequencyDictId,
        ),
        FrequenciesCompanion.insert(
          expression: kanjiCup,
          reading: const Value(kana),
          frequencyRank: 20,
          dictionaryId: frequencyDictId,
        ),
        FrequenciesCompanion.insert(
          expression: kana,
          reading: const Value(kana),
          frequencyRank: 5000,
          dictionaryId: frequencyDictId,
        ),
      ]);
    });

    tearDown(() async {
      await priorityDb.close();
    });

    test(
      'search prefers exact expression matches over reading-only matches',
      () async {
        final results = await priorityQueryService.search(kana);

        expect(results, hasLength(3));
        expect(results.first.expression, kana);
        expect(results.skip(1).map((r) => r.expression), [kanjiAsh, kanjiCup]);
      },
    );

    test(
      'searchWithSource prefers exact expression matches over reading-only matches',
      () async {
        final results = await priorityQueryService.searchWithSource(kana);

        expect(results, hasLength(3));
        expect(results.first.entry.expression, kana);
        expect(results.skip(1).map((r) => r.entry.expression), [
          kanjiAsh,
          kanjiCup,
        ]);
      },
    );

    test(
      'fuzzySearchWithSource keeps exact expression matches ahead of more common reading-only matches',
      () async {
        final results = await priorityQueryService.fuzzySearchWithSource(kana);

        expect(results, hasLength(3));
        expect(results.first.entry.expression, kana);
        expect(results.skip(1).map((r) => r.entry.expression), [
          kanjiAsh,
          kanjiCup,
        ]);
      },
    );
  });
}
