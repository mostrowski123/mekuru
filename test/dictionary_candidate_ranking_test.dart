import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_query_service.dart';

/// Candidate selection under LIMIT caps must be relevance-ordered, not
/// insertion-ordered. Before this ordering existed, `LIMIT n` picked rows in
/// rowid (= import) order, so whichever dictionary was imported first could
/// crowd the best match out of the candidate pool entirely — e.g. searching
/// "eat" filled the pool with "theater" glosses before 食べる's "to eat" was
/// ever considered.
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
  });

  tearDown(() async {
    await db.close();
  });

  test('prefix search keeps the shortest match even when inserted last, '
      'beyond the LIMIT cap', () async {
    final dictId = await repo.insertDictionary('Dict');

    // 60 long junk entries share the prefix and sort lexicographically
    // before the best completion (あかあ… < あかい), so both insertion
    // order and index order fill a limit-50 pool with junk.
    await repo.batchInsertEntries([
      for (var i = 0; i < 60; i++)
        DictionaryEntriesCompanion.insert(
          expression: 'あかあ長い言葉その$i',
          reading: Value('あかあながいことばその$i'),
          glossaries: jsonEncode(['junk $i']),
          dictionaryId: dictId,
        ),
      // The best (shortest) completion arrives last.
      DictionaryEntriesCompanion.insert(
        expression: 'あかい',
        reading: const Value('あかい'),
        glossaries: jsonEncode(['red']),
        dictionaryId: dictId,
      ),
    ]);

    final results = await queryService.prefixSearchWithSource('あか', limit: 50);

    expect(
      results.map((r) => r.entry.expression),
      contains('あかい'),
      reason: 'shortest prefix completion must survive the LIMIT cap',
    );
  });

  test('glossary search keeps the tightest gloss match even when inserted '
      'last, beyond the LIMIT cap', () async {
    final dictId = await repo.insertDictionary('Dict');

    await repo.batchInsertEntries([
      // 40 entries whose long glossaries contain "eat" only as a
      // substring of other words.
      for (var i = 0; i < 40; i++)
        DictionaryEntriesCompanion.insert(
          expression: '劇場$i',
          reading: Value('げきじょう$i'),
          glossaries: jsonEncode([
            'theater district building number $i with a beaten path',
          ]),
          dictionaryId: dictId,
        ),
      // The entry the user actually wants arrives last.
      DictionaryEntriesCompanion.insert(
        expression: '食べる',
        reading: const Value('たべる'),
        glossaries: jsonEncode(['to eat']),
        dictionaryId: dictId,
      ),
    ]);

    final direct = await queryService.glossarySearchWithSource(
      'eat',
      limit: 30,
    );
    expect(
      direct.map((r) => r.entry.expression),
      contains('食べる'),
      reason: 'tightest gloss match must survive the LIMIT cap',
    );

    // Same guarantee through the search-screen path (direct glossary
    // matches are capped at 30 internally).
    final fuzzy = await queryService.fuzzySearchWithSource('eat');
    expect(
      fuzzy.map((r) => r.entry.expression),
      contains('食べる'),
      reason: 'search screen must find 食べる for "eat"',
    );
  });
}
