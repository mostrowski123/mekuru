import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_query_service.dart';

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
  late int dictId;

  setUp(() async {
    db = createTestDatabase();
    repo = DictionaryRepository(db);
    queryService = DictionaryQueryService(db);

    dictId = await repo.insertDictionary('TestDict');

    await repo.batchInsertEntries([
      // Compound word
      DictionaryEntriesCompanion.insert(
        expression: '国立',
        reading: const Value('こくりつ'),
        glossaries: jsonEncode(['national']),
        dictionaryId: dictId,
      ),
      // Individual kanji
      DictionaryEntriesCompanion.insert(
        expression: '国',
        reading: const Value('くに'),
        glossaries: jsonEncode(['country', 'nation']),
        dictionaryId: dictId,
      ),
      DictionaryEntriesCompanion.insert(
        expression: '立',
        reading: const Value('たつ'),
        glossaries: jsonEncode(['to stand']),
        dictionaryId: dictId,
      ),
      // Words for prefix search
      DictionaryEntriesCompanion.insert(
        expression: '食べる',
        reading: const Value('たべる'),
        glossaries: jsonEncode(['to eat']),
        dictionaryId: dictId,
      ),
      DictionaryEntriesCompanion.insert(
        expression: '食べ物',
        reading: const Value('たべもの'),
        glossaries: jsonEncode(['food']),
        dictionaryId: dictId,
      ),
      DictionaryEntriesCompanion.insert(
        expression: '食べ放題',
        reading: const Value('たべほうだい'),
        glossaries: jsonEncode(['all-you-can-eat']),
        dictionaryId: dictId,
      ),
      // For romaji search
      DictionaryEntriesCompanion.insert(
        expression: '飲む',
        reading: const Value('のむ'),
        glossaries: jsonEncode(['to drink']),
        dictionaryId: dictId,
      ),
      DictionaryEntriesCompanion.insert(
        expression: '走る',
        reading: const Value('はしる'),
        glossaries: jsonEncode(['to run']),
        dictionaryId: dictId,
      ),
      // Katakana entry
      DictionaryEntriesCompanion.insert(
        expression: 'ラーメン',
        reading: const Value('らーめん'),
        glossaries: jsonEncode(['ramen']),
        dictionaryId: dictId,
      ),
    ]);
  });

  tearDown(() async {
    await db.close();
  });

  group('prefixSearchWithSource', () {
    test('finds entries by expression prefix', () async {
      final results = await queryService.prefixSearchWithSource('食べ');
      expect(results.length, greaterThanOrEqualTo(3));
      final expressions = results.map((r) => r.entry.expression).toSet();
      expect(expressions, contains('食べる'));
      expect(expressions, contains('食べ物'));
      expect(expressions, contains('食べ放題'));
    });

    test('finds entries by reading prefix', () async {
      final results = await queryService.prefixSearchWithSource('たべ');
      expect(results.length, greaterThanOrEqualTo(3));
    });

    test('returns empty for non-matching prefix', () async {
      final results = await queryService.prefixSearchWithSource('xyz');
      expect(results, isEmpty);
    });

    test('returns empty for empty term', () async {
      final results = await queryService.prefixSearchWithSource('');
      expect(results, isEmpty);
    });

    test('respects limit parameter', () async {
      final results = await queryService.prefixSearchWithSource('食べ', limit: 1);
      expect(results, hasLength(1));
    });
  });

  group('fuzzySearchWithSource', () {
    test('exact match appears first for kanji input', () async {
      final results = await queryService.fuzzySearchWithSource('国立');
      expect(results, isNotEmpty);
      // First result should be the exact match
      expect(results.first.entry.expression, '国立');
    });

    test('includes sub-component kanji matches', () async {
      final results = await queryService.fuzzySearchWithSource('国立');
      final expressions = results.map((r) => r.entry.expression).toList();
      expect(expressions, contains('国立'));
      expect(expressions, contains('国'));
      expect(expressions, contains('立'));
    });

    test('sub-component matches come after exact/prefix matches', () async {
      final results = await queryService.fuzzySearchWithSource('国立');
      final expressions = results.map((r) => r.entry.expression).toList();
      // 国立 should appear before 国 and 立
      final exactIdx = expressions.indexOf('国立');
      final kuniIdx = expressions.indexOf('国');
      final tatsuIdx = expressions.indexOf('立');
      expect(exactIdx, lessThan(kuniIdx));
      expect(exactIdx, lessThan(tatsuIdx));
    });

    test('handles romaji input by converting to hiragana', () async {
      final results = await queryService.fuzzySearchWithSource('nomu');
      expect(results, isNotEmpty);
      final expressions = results.map((r) => r.entry.expression).toSet();
      expect(expressions, contains('飲む'));
    });

    test('handles hiragana input', () async {
      final results = await queryService.fuzzySearchWithSource('たべる');
      expect(results, isNotEmpty);
      expect(results.first.entry.expression, '食べる');
    });

    test('handles katakana input with hiragana fallback', () async {
      final results = await queryService.fuzzySearchWithSource('ラーメン');
      expect(results, isNotEmpty);
      expect(results.first.entry.expression, 'ラーメン');
    });

    test('returns empty for no matches', () async {
      final results = await queryService.fuzzySearchWithSource('zzzzz');
      expect(results, isEmpty);
    });

    test('returns empty for empty input', () async {
      final results = await queryService.fuzzySearchWithSource('');
      expect(results, isEmpty);
    });

    test('deduplicates results', () async {
      final results = await queryService.fuzzySearchWithSource('国');
      final ids = results.map((r) => r.entry.id).toList();
      // No duplicate IDs
      expect(ids.toSet().length, ids.length);
    });

    test('prefix search finds words starting with term', () async {
      final results = await queryService.fuzzySearchWithSource('食べ');
      final expressions = results.map((r) => r.entry.expression).toSet();
      expect(expressions, contains('食べる'));
      expect(expressions, contains('食べ物'));
      expect(expressions, contains('食べ放題'));
    });

    test('romaji prefix search works for partial input', () async {
      // 'tabe' converts to 'たべ', should find 食べる etc.
      final results = await queryService.fuzzySearchWithSource('tabe');
      expect(results, isNotEmpty);
      final expressions = results.map((r) => r.entry.expression).toSet();
      expect(expressions, contains('食べる'));
    });

    test('includes dictionary name in results', () async {
      final results = await queryService.fuzzySearchWithSource('国立');
      for (final r in results) {
        expect(r.dictionaryName, 'TestDict');
      }
    });
  });

  group('glossarySearchWithSource', () {
    test('finds entries by English definition substring', () async {
      final results = await queryService.glossarySearchWithSource('eat');
      expect(results, isNotEmpty);
      final expressions = results.map((r) => r.entry.expression).toSet();
      expect(expressions, contains('食べる'));
      // 'all-you-can-eat' also contains 'eat'
      expect(expressions, contains('食べ放題'));
    });

    test('is case-insensitive', () async {
      final lower = await queryService.glossarySearchWithSource('drink');
      final upper = await queryService.glossarySearchWithSource('DRINK');
      expect(lower, isNotEmpty);
      expect(upper, isNotEmpty);
      expect(lower.first.entry.expression, upper.first.entry.expression);
    });

    test('finds entries by full definition word', () async {
      final results = await queryService.glossarySearchWithSource('national');
      expect(results, isNotEmpty);
      expect(results.first.entry.expression, '国立');
    });

    test('finds entries by partial word match', () async {
      final results = await queryService.glossarySearchWithSource('coun');
      expect(results, isNotEmpty);
      expect(results.first.entry.expression, '国');
    });

    test('returns empty for non-matching term', () async {
      final results = await queryService.glossarySearchWithSource(
        'nonexistentword',
      );
      expect(results, isEmpty);
    });

    test('returns empty for empty term', () async {
      final results = await queryService.glossarySearchWithSource('');
      expect(results, isEmpty);
    });

    test('respects limit parameter', () async {
      final results = await queryService.glossarySearchWithSource(
        'to',
        limit: 2,
      );
      expect(results.length, lessThanOrEqualTo(2));
    });

    test('excludes disabled dictionaries', () async {
      // Create a separate DB with disabled dict
      final db2 = createTestDatabase();
      final repo2 = DictionaryRepository(db2);
      final qs2 = DictionaryQueryService(db2);

      final enabledId = await repo2.insertDictionary('Enabled');
      final disabledId = await repo2.insertDictionary('Disabled');
      await repo2.toggleDictionary(disabledId, isEnabled: false);

      await repo2.batchInsertEntries([
        DictionaryEntriesCompanion.insert(
          expression: '犬',
          reading: const Value('いぬ'),
          glossaries: jsonEncode(['dog']),
          dictionaryId: enabledId,
        ),
        DictionaryEntriesCompanion.insert(
          expression: '猫',
          reading: const Value('ねこ'),
          glossaries: jsonEncode(['cat', 'dog-like']),
          dictionaryId: disabledId,
        ),
      ]);

      final results = await qs2.glossarySearchWithSource('dog');
      expect(results, hasLength(1));
      expect(results.first.entry.expression, '犬');
      await db2.close();
    });
  });

  group('fuzzySearchWithSource — English definition search', () {
    test('English input finds entries via glossary definitions', () async {
      final results = await queryService.fuzzySearchWithSource('drink');
      expect(results, isNotEmpty);
      final expressions = results.map((r) => r.entry.expression).toSet();
      expect(expressions, contains('飲む'));
    });

    test('English input "eat" finds 食べる', () async {
      final results = await queryService.fuzzySearchWithSource('eat');
      expect(results, isNotEmpty);
      final expressions = results.map((r) => r.entry.expression).toSet();
      expect(expressions, contains('食べる'));
    });

    test('English input "food" finds 食べ物', () async {
      final results = await queryService.fuzzySearchWithSource('food');
      expect(results, isNotEmpty);
      final expressions = results.map((r) => r.entry.expression).toSet();
      expect(expressions, contains('食べ物'));
    });

    test('English input "ramen" finds ラーメン', () async {
      final results = await queryService.fuzzySearchWithSource('ramen');
      expect(results, isNotEmpty);
      final expressions = results.map((r) => r.entry.expression).toSet();
      expect(expressions, contains('ラーメン'));
    });

    test('English input "run" finds 走る', () async {
      final results = await queryService.fuzzySearchWithSource('run');
      expect(results, isNotEmpty);
      final expressions = results.map((r) => r.entry.expression).toSet();
      expect(expressions, contains('走る'));
    });

    test('English input with spaces works', () async {
      final results = await queryService.fuzzySearchWithSource('to stand');
      expect(results, isNotEmpty);
      final expressions = results.map((r) => r.entry.expression).toSet();
      expect(expressions, contains('立'));
    });

    test('romaji input still finds by reading AND by glossary', () async {
      // 'nomu' converts to 'のむ' → finds 飲む via reading
      // 'nomu' is also ASCII → glossary search (won't match anything extra)
      final results = await queryService.fuzzySearchWithSource('nomu');
      expect(results, isNotEmpty);
      expect(results.first.entry.expression, '飲む');
    });

    test('deduplicates entries found via both romaji and glossary', () async {
      // 'ramen' converts to 'らめん' (partial) → might match ラーメン via reading prefix
      // 'ramen' also matches glossary → ラーメン
      // Should not have duplicates
      final results = await queryService.fuzzySearchWithSource('ramen');
      final ids = results.map((r) => r.entry.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('non-ASCII input does not trigger glossary search', () async {
      // Pure Japanese input should not search glossaries
      // (testing indirectly: searching for 'country' in Japanese won't work)
      final results = await queryService.fuzzySearchWithSource('くに');
      // Should find 国 by reading, but not via glossary
      expect(results, isNotEmpty);
      expect(results.first.entry.expression, '国');
    });
  });

  group('fuzzySearchWithSource — disabled dictionaries', () {
    late AppDatabase db2;
    late DictionaryRepository repo2;
    late DictionaryQueryService queryService2;

    setUp(() async {
      db2 = createTestDatabase();
      repo2 = DictionaryRepository(db2);
      queryService2 = DictionaryQueryService(db2);

      final enabledId = await repo2.insertDictionary('Enabled');
      final disabledId = await repo2.insertDictionary('Disabled');
      await repo2.toggleDictionary(disabledId, isEnabled: false);

      await repo2.batchInsertEntries([
        DictionaryEntriesCompanion.insert(
          expression: '国',
          reading: const Value('くに'),
          glossaries: jsonEncode(['country (enabled)']),
          dictionaryId: enabledId,
        ),
        DictionaryEntriesCompanion.insert(
          expression: '国',
          reading: const Value('くに'),
          glossaries: jsonEncode(['country (disabled)']),
          dictionaryId: disabledId,
        ),
      ]);
    });

    tearDown(() async {
      await db2.close();
    });

    test('excludes disabled dictionary entries', () async {
      final results = await queryService2.fuzzySearchWithSource('国');
      expect(results, hasLength(1));
      expect(results.first.dictionaryName, 'Enabled');
    });
  });

  group('fuzzySearchWithSource — ambiguous romaji readings', () {
    late AppDatabase db2;
    late DictionaryRepository repo2;
    late DictionaryQueryService queryService2;

    setUp(() async {
      db2 = createTestDatabase();
      repo2 = DictionaryRepository(db2);
      queryService2 = DictionaryQueryService(db2);

      final entriesId = await repo2.insertDictionary('Entries');
      await repo2.batchInsertEntries([
        DictionaryEntriesCompanion.insert(
          expression: '恋愛',
          reading: const Value('れんあい'),
          glossaries: jsonEncode(['love', 'romance']),
          dictionaryId: entriesId,
        ),
        DictionaryEntriesCompanion.insert(
          expression: '記念',
          reading: const Value('きねん'),
          glossaries: jsonEncode(['commemoration']),
          dictionaryId: entriesId,
        ),
        DictionaryEntriesCompanion.insert(
          expression: '禁煙',
          reading: const Value('きんえん'),
          glossaries: jsonEncode(['no smoking']),
          dictionaryId: entriesId,
        ),
        DictionaryEntriesCompanion.insert(
          expression: '新聞',
          reading: const Value('しんぶん'),
          glossaries: jsonEncode(['newspaper']),
          dictionaryId: entriesId,
        ),
        DictionaryEntriesCompanion.insert(
          expression: '学校',
          reading: const Value('がっこう'),
          glossaries: jsonEncode(['school']),
          dictionaryId: entriesId,
        ),
        DictionaryEntriesCompanion.insert(
          expression: '個',
          reading: const Value('こ'),
          glossaries: jsonEncode(['counter for articles']),
          dictionaryId: entriesId,
        ),
        DictionaryEntriesCompanion.insert(
          expression: '高',
          reading: const Value('こう'),
          glossaries: jsonEncode(['high; expensive']),
          dictionaryId: entriesId,
        ),
      ]);

      // Frequency-only install pattern: disabled + hidden, ranks still apply.
      final freqDictId = await repo2.insertDictionary('FreqDict');
      await repo2.batchInsertFrequencies([
        FrequenciesCompanion.insert(
          expression: '恋愛',
          reading: const Value('れんあい'),
          frequencyRank: 500,
          dictionaryId: freqDictId,
        ),
        FrequenciesCompanion.insert(
          expression: '記念',
          reading: const Value('きねん'),
          frequencyRank: 900,
          dictionaryId: freqDictId,
        ),
        FrequenciesCompanion.insert(
          expression: '禁煙',
          reading: const Value('きんえん'),
          frequencyRank: 100,
          dictionaryId: freqDictId,
        ),
        FrequenciesCompanion.insert(
          expression: '学校',
          reading: const Value('がっこう'),
          frequencyRank: 300,
          dictionaryId: freqDictId,
        ),
        FrequenciesCompanion.insert(
          expression: '個',
          reading: const Value('こ'),
          frequencyRank: 400,
          dictionaryId: freqDictId,
        ),
        FrequenciesCompanion.insert(
          expression: '高',
          reading: const Value('こう'),
          frequencyRank: 50,
          dictionaryId: freqDictId,
        ),
      ]);
      await repo2.toggleDictionary(freqDictId, isEnabled: false);
      await repo2.setHidden(freqDictId, isHidden: true);
    });

    tearDown(() async {
      await db2.close();
    });

    test("finds 恋愛 via 'rennai', 'renai', and \"ren'ai\"", () async {
      for (final query in ['rennai', 'renai', "ren'ai"]) {
        final results = await queryService2.fuzzySearchWithSource(query);
        final expressions = results.map((r) => r.entry.expression).toSet();
        expect(expressions, contains('恋愛'), reason: query);
      }
    });

    test(
      'alternative readings rank by frequency among exact matches',
      () async {
        final results = await queryService2.fuzzySearchWithSource('kinen');
        final expressions = results.map((r) => r.entry.expression).toList();
        expect(expressions, contains('記念'));
        expect(expressions, contains('禁煙'));
        // 禁煙 (rank 100) is more common than 記念 (rank 900), so the word from
        // the alternative reading comes first — alternative readings compete as
        // first-class exact matches.
        expect(expressions.indexOf('禁煙'), lessThan(expressions.indexOf('記念')));
      },
    );

    test('unambiguous romaji is unaffected', () async {
      final results = await queryService2.fuzzySearchWithSource('shinbun');
      expect(results, isNotEmpty);
      expect(results.first.entry.expression, '新聞');
    });

    test('finds 学校 when the trailing long vowel is omitted', () async {
      for (final query in ['gakko', 'がっこ']) {
        final results = await queryService2.fuzzySearchWithSource(query);
        expect(results, isNotEmpty, reason: query);
        // The completed reading がっこう is an exact-tier match, so 学校
        // leads the results rather than surfacing as a fuzzy afterthought.
        expect(results.first.entry.expression, '学校', reason: query);
      }
    });

    test('single-kana input is not flooded by completions', () async {
      // 高/こう (rank 50) must not ride a こ→こう completion into the exact
      // tier above the as-typed 個/こ (rank 400): completions only apply to
      // kana terms of two or more characters.
      final results = await queryService2.fuzzySearchWithSource('こ');
      expect(results, isNotEmpty);
      expect(results.first.entry.expression, '個');

      // Typing the full word still finds it first.
      final kou = await queryService2.fuzzySearchWithSource('こう');
      expect(kou.first.entry.expression, '高');
    });
  });
}
