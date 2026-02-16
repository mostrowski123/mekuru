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
      final results = await queryService.prefixSearchWithSource(
        '食べ',
        limit: 1,
      );
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
}
