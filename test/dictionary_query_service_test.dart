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
}
