import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_query_service.dart';

/// English glossary lookup runs on an FTS5 index (dictionary_entries_fts)
/// instead of a full-table LIKE scan. These tests pin the index lifecycle
/// (created on open, kept in sync by triggers, rebuildable) and the
/// word-boundary + relevance semantics that FTS provides.
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

  DictionaryEntriesCompanion entry(
    String expression,
    String reading,
    String gloss, [
    int? dictionaryId,
  ]) {
    return DictionaryEntriesCompanion.insert(
      expression: expression,
      reading: Value(reading),
      glossaries: jsonEncode([gloss]),
      dictionaryId: dictionaryId ?? dictId,
    );
  }

  setUp(() async {
    db = createTestDatabase();
    repo = DictionaryRepository(db);
    queryService = DictionaryQueryService(db);
    dictId = await repo.insertDictionary('Dict');
  });

  tearDown(() async {
    await db.close();
  });

  group('FTS schema lifecycle', () {
    test(
      'opening the database creates the FTS table and sync triggers',
      () async {
        final names =
            (await db
                    .customSelect(
                      "SELECT name FROM sqlite_master "
                      "WHERE name LIKE 'dictionary_entries_fts%' "
                      "OR type = 'trigger'",
                    )
                    .get())
                .map((r) => r.data['name'])
                .toSet();

        expect(names, contains('dictionary_entries_fts'));
        expect(names, contains('dictionary_entries_fts_ai'));
        expect(names, contains('dictionary_entries_fts_ad'));
        expect(names, contains('dictionary_entries_fts_au'));
      },
    );

    test(
      'rebuild repairs the index when it was lost, covering all rows',
      () async {
        await repo.batchInsertEntries([entry('食べる', 'たべる', 'to eat')]);

        // Simulate a database whose FTS index was lost (e.g. an install
        // predating the index): drop table + triggers, then add rows that
        // the triggers would have missed.
        for (final trigger in ['ai', 'ad', 'au']) {
          await db.customStatement(
            'DROP TRIGGER dictionary_entries_fts_$trigger',
          );
        }
        await db.customStatement('DROP TABLE dictionary_entries_fts');
        await repo.batchInsertEntries([entry('飲む', 'のむ', 'to drink')]);

        await db.ensureGlossaryFtsForTesting();

        final eat = await queryService.glossarySearchWithSource('eat');
        final drink = await queryService.glossarySearchWithSource('drink');
        expect(eat.map((r) => r.entry.expression), contains('食べる'));
        expect(drink.map((r) => r.entry.expression), contains('飲む'));
      },
    );
  });

  group('trigger synchronization', () {
    test('rows inserted after open are searchable', () async {
      await repo.batchInsertEntries([entry('走る', 'はしる', 'to run')]);
      final results = await queryService.glossarySearchWithSource('run');
      expect(results.map((r) => r.entry.expression), contains('走る'));
    });

    test('updated glossaries are reflected in search', () async {
      await repo.batchInsertEntries([entry('走る', 'はしる', 'to run')]);
      await (db.update(
        db.dictionaryEntries,
      )..where((t) => t.expression.equals('走る'))).write(
        DictionaryEntriesCompanion(
          glossaries: Value(jsonEncode(['to sprint'])),
        ),
      );

      expect(await queryService.glossarySearchWithSource('run'), isEmpty);
      final sprint = await queryService.glossarySearchWithSource('sprint');
      expect(sprint.map((r) => r.entry.expression), contains('走る'));
    });

    test('deleted rows disappear from search', () async {
      await repo.batchInsertEntries([entry('走る', 'はしる', 'to run')]);
      await (db.delete(
        db.dictionaryEntries,
      )..where((t) => t.expression.equals('走る'))).go();

      expect(await queryService.glossarySearchWithSource('run'), isEmpty);
    });

    test('deleting a dictionary removes its entries from search', () async {
      await repo.batchInsertEntries([entry('走る', 'はしる', 'to run')]);
      await repo.deleteDictionary(dictId);

      expect(await queryService.glossarySearchWithSource('run'), isEmpty);
    });
  });

  group('word-boundary matching', () {
    setUp(() async {
      await repo.batchInsertEntries([
        entry('走る', 'はしる', 'to run'),
        entry('梅干し', 'うめぼし', 'dried plum; prune juice ingredient'),
        entry('食べる', 'たべる', 'to eat'),
        entry('劇場', 'げきじょう', 'theater district building'),
      ]);
    });

    test('matches whole words, not substrings inside other words', () async {
      final run = await queryService.glossarySearchWithSource('run');
      expect(run.map((r) => r.entry.expression), contains('走る'));
      expect(
        run.map((r) => r.entry.expression),
        isNot(contains('梅干し')),
        reason: '"run" inside "prune" must not match',
      );

      final eat = await queryService.glossarySearchWithSource('eat');
      expect(eat.map((r) => r.entry.expression), contains('食べる'));
      expect(
        eat.map((r) => r.entry.expression),
        isNot(contains('劇場')),
        reason: '"eat" inside "theater" must not match',
      );
    });

    test(
      'search-screen English lookup no longer surfaces substring noise',
      () async {
        final results = await queryService.fuzzySearchWithSource('eat');
        final expressions = results.map((r) => r.entry.expression).toList();
        expect(expressions, contains('食べる'));
        expect(expressions, isNot(contains('劇場')));
      },
    );

    test('prefix typing matches (search-as-you-type)', () async {
      final results = await queryService.glossarySearchWithSource('ea');
      expect(results.map((r) => r.entry.expression), contains('食べる'));
    });

    test('multi-word phrases match', () async {
      final results = await queryService.glossarySearchWithSource('to eat');
      expect(results.map((r) => r.entry.expression), contains('食べる'));
    });

    test('stemmed forms match (porter tokenizer)', () async {
      final results = await queryService.glossarySearchWithSource('running');
      expect(results.map((r) => r.entry.expression), contains('走る'));
    });

    test('matching is case-insensitive', () async {
      final results = await queryService.glossarySearchWithSource('EAT');
      expect(results.map((r) => r.entry.expression), contains('食べる'));
    });
  });

  group('relevance and safety', () {
    test('tight glosses rank above long glosses containing the term', () async {
      await repo.batchInsertEntries([
        entry(
          '長文',
          'ちょうぶん',
          'a very long explanatory gloss that happens to mention '
              'the word eat somewhere in the middle of many other words',
        ),
        entry('食べる', 'たべる', 'to eat'),
      ]);

      final results = await queryService.glossarySearchWithSource('eat');
      expect(results.first.entry.expression, '食べる');
    });

    test('embedded quotes and FTS syntax do not throw', () async {
      await repo.batchInsertEntries([entry('食べる', 'たべる', 'to eat')]);

      expect(
        await queryService.glossarySearchWithSource('ea"t OR NEAR('),
        isEmpty,
      );
      expect(await queryService.glossarySearchWithSource('"eat"'), isNotEmpty);
    });

    test(
      'terms with no indexable content return empty without error',
      () async {
        await repo.batchInsertEntries([entry('食べる', 'たべる', 'to eat')]);
        expect(await queryService.glossarySearchWithSource('!!!'), isEmpty);
      },
    );

    test('excludes disabled dictionaries', () async {
      final disabledId = await repo.insertDictionary('Disabled');
      await repo.toggleDictionary(disabledId, isEnabled: false);
      await repo.batchInsertEntries([
        entry('走る', 'はしる', 'to run'),
        entry('駆ける', 'かける', 'to run fast', disabledId),
      ]);

      final results = await queryService.glossarySearchWithSource('run');
      expect(results.map((r) => r.entry.expression), contains('走る'));
      expect(results.map((r) => r.entry.expression), isNot(contains('駆ける')));
    });
  });
}
