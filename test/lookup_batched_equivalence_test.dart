import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_query_service.dart';

/// Exercises the hard invariant in the perf plan: the batched lookup path
/// (`kUseBatchedDictionaryLookup = true`) must return byte-identical results
/// and ordering to the legacy per-tier / per-candidate path.
///
/// Any diff here is a regression and blocks the optimization from shipping.

AppDatabase _createDb() => AppDatabase(NativeDatabase.memory());

Future<void> _seedDictionaries(DictionaryRepository repo) async {
  final dictA = await repo.insertDictionary('DictA', sortOrder: 0);
  final dictB = await repo.insertDictionary('DictB', sortOrder: 1);
  final dictDisabled = await repo.insertDictionary('Disabled', sortOrder: 2);
  await repo.toggleDictionary(dictDisabled, isEnabled: false);

  await repo.batchInsertEntries([
    // 食べる / たべる — two entries same (expr, reading) across dicts
    DictionaryEntriesCompanion.insert(
      expression: '食べる',
      reading: const Value('たべる'),
      glossaries: jsonEncode(['to eat']),
      dictionaryId: dictA,
    ),
    DictionaryEntriesCompanion.insert(
      expression: '食べる',
      reading: const Value('たべる'),
      glossaries: jsonEncode(['to eat (B)']),
      dictionaryId: dictB,
    ),
    // 食べた (inflected form) — exists as surface in dictA
    DictionaryEntriesCompanion.insert(
      expression: '食べた',
      reading: const Value('たべた'),
      glossaries: jsonEncode(['ate']),
      dictionaryId: dictA,
    ),
    // 走る / はしる — single entry
    DictionaryEntriesCompanion.insert(
      expression: '走る',
      reading: const Value('はしる'),
      glossaries: jsonEncode(['to run']),
      dictionaryId: dictA,
    ),
    // 行く / いく — only reading in dictB
    DictionaryEntriesCompanion.insert(
      expression: '行く',
      reading: const Value('いく'),
      glossaries: jsonEncode(['to go']),
      dictionaryId: dictB,
    ),
    // 私 with two readings — cross-tier overlap scenario
    DictionaryEntriesCompanion.insert(
      expression: '私',
      reading: const Value('わたし'),
      glossaries: jsonEncode(['I']),
      dictionaryId: dictA,
    ),
    DictionaryEntriesCompanion.insert(
      expression: '私',
      reading: const Value('わたくし'),
      glossaries: jsonEncode(['I (formal)']),
      dictionaryId: dictA,
    ),
    // Disabled-dict entry: must NOT appear under either path
    DictionaryEntriesCompanion.insert(
      expression: '食べる',
      reading: const Value('たべる'),
      glossaries: jsonEncode(['to eat (disabled)']),
      dictionaryId: dictDisabled,
    ),
  ]);

  await repo.batchInsertFrequencies([
    FrequenciesCompanion.insert(
      expression: '食べる',
      reading: const Value('たべる'),
      frequencyRank: 500,
      dictionaryId: dictA,
    ),
    FrequenciesCompanion.insert(
      expression: '私',
      reading: const Value('わたし'),
      frequencyRank: 100,
      dictionaryId: dictA,
    ),
    FrequenciesCompanion.insert(
      expression: '走る',
      reading: const Value(''),
      frequencyRank: 2500,
      dictionaryId: dictA,
    ),
  ]);
}

String _fingerprint(List<DictionaryEntryWithSource> results) {
  return results
      .map(
        (r) =>
            '${r.entry.id}|${r.entry.expression}|${r.entry.reading}|'
            '${r.dictionaryName}|${r.frequencyRank}',
      )
      .join(';');
}

Future<List<DictionaryEntryWithSource>> _runUnderFlag(
  DictionaryQueryService service,
  bool batched,
  Future<List<DictionaryEntryWithSource>> Function() op,
) async {
  final previous = kUseBatchedDictionaryLookup;
  kUseBatchedDictionaryLookup = batched;
  service.invalidateMetasCache();
  try {
    return await op();
  } finally {
    kUseBatchedDictionaryLookup = previous;
    service.invalidateMetasCache();
  }
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
  late DictionaryQueryService service;

  setUp(() async {
    db = _createDb();
    repo = DictionaryRepository(db);
    service = DictionaryQueryService(db);
    await _seedDictionaries(repo);
  });

  tearDown(() async {
    await db.close();
  });

  group('searchLookupWithSource — batched vs legacy equivalence', () {
    const queries = <({String primary, String? secondary})>[
      (primary: '食べる', secondary: null),
      (primary: '食べた', secondary: null),
      (primary: '食べる', secondary: '食べた'),
      (primary: 'たべる', secondary: null),
      (primary: 'わたし', secondary: '私'),
      (primary: '行く', secondary: 'いく'),
      (primary: '走る', secondary: null),
      (primary: '存在しない', secondary: null),
    ];

    for (final q in queries) {
      test('primary="${q.primary}" secondary="${q.secondary}"', () async {
        final legacy = await _runUnderFlag(
          service,
          false,
          () => service.searchLookupWithSource(q.primary, q.secondary),
        );
        final batched = await _runUnderFlag(
          service,
          true,
          () => service.searchLookupWithSource(q.primary, q.secondary),
        );
        expect(
          _fingerprint(batched),
          equals(_fingerprint(legacy)),
          reason: 'batched path diverged for "${q.primary}"/"${q.secondary}"',
        );
      });
    }
  });

  group('matchingTerms vs hasMatch — equivalence', () {
    test('returns the same membership set as per-term hasMatch calls',
        () async {
      service.invalidateMetasCache();
      final terms = <String>[
        '食べる',
        '食べた',
        '走る',
        '行く',
        'わたし',
        '私',
        '存在しない',
        '',
      ];

      final expected = <String>{};
      for (final t in terms) {
        if (t.isEmpty) continue;
        if (await service.hasMatch(t)) expected.add(t);
      }

      final actual = await service.matchingTerms(terms);
      expect(actual, equals(expected));
    });
  });
}
