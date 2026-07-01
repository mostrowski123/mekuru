import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_query_service.dart';

/// Characterization tests for prefix search behavior. These pin the
/// observable contract of [DictionaryQueryService.prefixSearchWithSource]
/// (and the candidate fetch used by fuzzy search, which shares the same
/// matching condition) so the LIKE → indexed-range-scan swap can't silently
/// change results.
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

  DictionaryEntriesCompanion entry(
    String expression,
    String reading,
    int dictId, [
    String gloss = 'gloss',
  ]) {
    return DictionaryEntriesCompanion.insert(
      expression: expression,
      reading: Value(reading),
      glossaries: jsonEncode([gloss]),
      dictionaryId: dictId,
    );
  }

  setUp(() async {
    db = createTestDatabase();
    repo = DictionaryRepository(db);
    queryService = DictionaryQueryService(db);

    final enabledId = await repo.insertDictionary('EnabledDict');
    final disabledId = await repo.insertDictionary('DisabledDict');
    await repo.toggleDictionary(disabledId, isEnabled: false);

    await repo.batchInsertEntries([
      entry('日本', 'にほん', enabledId),
      entry('日本語', 'にほんご', enabledId),
      entry('日程', 'にってい', enabledId),
      // Boundary probe: が sorts immediately after か — a range scan with a
      // wrong upper bound would leak this into a 'か' prefix search.
      entry('かめ', 'かめ', enabledId),
      entry('がめん', 'がめん', enabledId),
      // ASCII expression — LIKE matches case-insensitively today.
      entry('DVD', 'ディーブイディー', enabledId),
      // Astral (surrogate-pair) leading code point.
      entry('𩸽定食', 'ほっけていしょく', enabledId),
      // Only in the disabled dictionary — must never surface.
      entry('日本刀', 'にほんとう', disabledId),
    ]);
  });

  tearDown(() async {
    await db.close();
  });

  group('prefixSearchWithSource', () {
    test('matches expressions by prefix', () async {
      final results = await queryService.prefixSearchWithSource('日本');
      final expressions = results.map((r) => r.entry.expression).toSet();
      expect(expressions, {'日本', '日本語'});
    });

    test('matches readings by prefix', () async {
      final results = await queryService.prefixSearchWithSource('にほ');
      final expressions = results.map((r) => r.entry.expression).toSet();
      expect(expressions, {'日本', '日本語'});
    });

    test('does not leak entries past the prefix boundary', () async {
      final results = await queryService.prefixSearchWithSource('か');
      final expressions = results.map((r) => r.entry.expression).toSet();
      expect(expressions, {'かめ'});
    });

    test('matches ASCII expressions case-insensitively', () async {
      final results = await queryService.prefixSearchWithSource('dvd');
      expect(results.map((r) => r.entry.expression), contains('DVD'));
    });

    test('matches expressions starting with astral code points', () async {
      final results = await queryService.prefixSearchWithSource('𩸽');
      expect(results.map((r) => r.entry.expression), contains('𩸽定食'));
    });

    test('never returns entries from disabled dictionaries', () async {
      final results = await queryService.prefixSearchWithSource('日本');
      expect(
        results.map((r) => r.entry.expression),
        isNot(contains('日本刀')),
      );
    });

    test('returns empty for empty term', () async {
      expect(await queryService.prefixSearchWithSource(''), isEmpty);
    });
  });
}
