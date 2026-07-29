import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_query_service.dart';
import 'package:mekuru/features/dictionary/data/services/glossary_parser.dart';

import 'dictionary_fts_test_support.dart';

/// English glossary lookup runs on an FTS5 index (dictionary_entries_fts)
/// instead of a full-table LIKE scan. These tests pin the index lifecycle
/// (created on open, kept in sync by triggers, rebuildable) and the
/// word-boundary + relevance semantics that FTS provides.
AppDatabase createTestDatabase() {
  return AppDatabase(NativeDatabase.memory());
}

/// Yomitan structured-content shape used by recent JMdict releases:
/// the gloss text sits inside nested content/tag markup.
String structured(List<String> glosses) {
  return jsonEncode([
    jsonEncode({
      'type': 'structured-content',
      'content': {
        'tag': 'ul',
        'style': {'listStyleType': 'circle'},
        'data': {'content': 'glossary'},
        'content': [
          for (final g in glosses) {'tag': 'li', 'content': g},
        ],
      },
    }),
  ]);
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
        await dropGlossaryFtsTriggersForTest(db);
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

  group('bulk FTS load', () {
    test('bulk indexing in a transaction matches trigger indexing', () async {
      await db.transaction(() async {
        await repo.beginGlossaryFtsBulkLoad();
        await repo.batchInsertEntries([
          entry('食べる', 'たべる', 'to eat'),
          entry('飲む', 'のむ', 'to drink'),
        ]);
        await repo.finishGlossaryFtsBulkLoad(dictId);
      });

      final eat = await queryService.glossarySearchWithSource('eat');
      expect(eat.map((r) => r.entry.expression), contains('食べる'));
      await expectGlossaryFtsConsistent(db);

      // Triggers are back and firing after the bulk load.
      await repo.batchInsertEntries([entry('走る', 'はしる', 'to run')]);
      final run = await queryService.glossarySearchWithSource('run');
      expect(run.map((r) => r.entry.expression), contains('走る'));
    });

    test('bulk load no-ops when the FTS index is missing', () async {
      // The FTS-lost state: bulk load must not throw, and the rebuild
      // path recovers the rows afterwards.
      await dropGlossaryFtsTriggersForTest(db);
      await db.customStatement('DROP TABLE dictionary_entries_fts');

      await db.transaction(() async {
        await repo.beginGlossaryFtsBulkLoad();
        await repo.batchInsertEntries([entry('食べる', 'たべる', 'to eat')]);
        await repo.finishGlossaryFtsBulkLoad(dictId);
      });

      await db.ensureGlossaryFtsForTesting();
      final eat = await queryService.glossarySearchWithSource('eat');
      expect(eat.map((r) => r.entry.expression), contains('食べる'));
    });
  });

  group('trigger synchronization', () {
    test('rows inserted after open are searchable', () async {
      await repo.batchInsertEntries([entry('走る', 'はしる', 'to run')]);
      final results = await queryService.glossarySearchWithSource('run');
      expect(results.map((r) => r.entry.expression), contains('走る'));
    });

    test('updated glossaries are reflected in search', () async {
      // Writers that change glossaries must refresh searchText too — the
      // FTS index tokenizes searchText, and its sync trigger fires on
      // updates of that column.
      await repo.batchInsertEntries([entry('走る', 'はしる', 'to run')]);
      final newGlossaries = jsonEncode(['to sprint']);
      await (db.update(
        db.dictionaryEntries,
      )..where((t) => t.expression.equals('走る'))).write(
        DictionaryEntriesCompanion(
          glossaries: Value(newGlossaries),
          searchText: Value(GlossaryParser.searchText(newGlossaries)),
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

  group('structured-content glossaries', () {
    test('gloss text inside structured content is searchable', () async {
      await repo.batchInsertEntries([
        DictionaryEntriesCompanion.insert(
          expression: '学校',
          reading: const Value('がっこう'),
          glossaries: structured(['school']),
          dictionaryId: dictId,
        ),
      ]);

      final results = await queryService.glossarySearchWithSource('school');
      expect(results.map((r) => r.entry.expression), contains('学校'));
    });

    test('structured-content markup noise is not indexed', () async {
      await repo.batchInsertEntries([
        DictionaryEntriesCompanion.insert(
          expression: '学校',
          reading: const Value('がっこう'),
          glossaries: structured(['school']),
          dictionaryId: dictId,
        ),
      ]);

      // Tokens from the JSON wrapper ("content", "tag", "li", "glossary",
      // "circle", …) polluted the old index and skewed bm25 ranking.
      for (final noise in ['content', 'tag', 'li', 'glossary', 'circle']) {
        expect(
          await queryService.glossarySearchWithSource(noise),
          isEmpty,
          reason: 'markup token "$noise" must not be searchable',
        );
      }
    });

    test('whole-gloss matches outrank tighter partial glosses '
        'even for multi-sense entries', () async {
      await repo.batchInsertEntries([
        // Multi-sense primary word: bm25 dilutes "teacher" across many
        // glosses, but "teacher" is exactly one of its definitions.
        DictionaryEntriesCompanion.insert(
          expression: '先生',
          reading: const Value('せんせい'),
          glossaries: structured([
            'teacher',
            'instructor',
            'master',
            'doctor',
            'with all due respect',
          ]),
          dictionaryId: dictId,
        ),
        // Short single-gloss entry that merely contains the term — the
        // stronger bm25 score must not beat the whole-gloss match.
        entry('ひいき生徒', 'ひいきせいと', "teacher's pet"),
      ]);

      final results = await queryService.glossarySearchWithSource('teacher');
      expect(results.first.entry.expression, '先生');
    });

    test('"to <term>" and parenthesized glosses count as whole-gloss '
        'matches', () async {
      await repo.batchInsertEntries([
        entry('食べる', 'たべる', 'to eat'),
        entry('食堂車', 'しょくどうしゃ', 'dining car where people eat meals on trains'),
        DictionaryEntriesCompanion.insert(
          expression: '水',
          reading: const Value('みず'),
          glossaries: structured(['water (esp. cool or cold)']),
          dictionaryId: dictId,
        ),
        entry('防水', 'ぼうすい', 'waterproofing'),
      ]);

      final eat = await queryService.glossarySearchWithSource('eat');
      expect(eat.first.entry.expression, '食べる');

      final water = await queryService.glossarySearchWithSource('water');
      final waterExprs = water.map((r) => r.entry.expression).toList();
      expect(
        waterExprs.indexOf('水'),
        lessThan(waterExprs.indexOf('防水')),
        reason: 'whole-gloss "water (…)" must outrank prefix-only matches',
      );
    });

    test('"to be/get/become <term>" glosses count as whole-gloss '
        'matches', () async {
      await repo.batchInsertEntries([
        entry('怒る', 'おこる', 'to get angry'),
        entry('怒号', 'どごう', 'angry roar'),
        entry('疲れる', 'つかれる', 'to become tired'),
        entry('疲労感', 'ひろうかん', 'tired feeling'),
      ]);

      // The short contains-matches score better on bm25; the framed
      // whole-gloss verbs must still come first.
      final angry = await queryService.glossarySearchWithSource('angry');
      expect(angry.first.entry.expression, '怒る');

      final tired = await queryService.glossarySearchWithSource('tired');
      expect(tired.first.entry.expression, '疲れる');
    });

    test('single characters match whole tokens, not prefixes', () async {
      await repo.batchInsertEntries([
        entry('私', 'わたし', 'I'),
        entry('氷', 'こおり', 'ice'),
      ]);

      // "i"* would match every gloss containing an i… word; as a whole
      // token it finds only glosses where "i" stands alone.
      final single = await queryService.glossarySearchWithSource('i');
      expect(single.map((r) => r.entry.expression), contains('私'));
      expect(single.map((r) => r.entry.expression), isNot(contains('氷')));

      // From two characters on, prefix semantics resume.
      final two = await queryService.glossarySearchWithSource('ic');
      expect(two.map((r) => r.entry.expression), contains('氷'));
    });

    test('search screen: a frequent word that merely mentions the term '
        'cannot outrank the word that means it', () async {
      await repo.batchInsertEntries([
        entry('食べる', 'たべる', 'to eat'),
        entry('やる', 'やる', 'to eat or drink (casually)'),
      ]);
      await db
          .into(db.frequencies)
          .insert(
            FrequenciesCompanion.insert(
              expression: 'やる',
              frequencyRank: 1,
              dictionaryId: dictId,
            ),
          );
      await db
          .into(db.frequencies)
          .insert(
            FrequenciesCompanion.insert(
              expression: '食べる',
              frequencyRank: 200,
              dictionaryId: dictId,
            ),
          );

      final results = await queryService.fuzzySearchWithSource('eat');
      final exprs = results.map((r) => r.entry.expression).toList();
      expect(
        exprs.indexOf('食べる'),
        lessThan(exprs.indexOf('やる')),
        reason:
            'whole-gloss match must rank above a higher-frequency '
            'contains-match in the glossary tier',
      );
    });
  });

  group('index shape upgrade', () {
    test(
      'an index over raw glossaries JSON is rebuilt over search text',
      () async {
        // Recreate the pre-search_text world: FTS over raw glossaries and
        // rows whose search_text was never populated (inserted via raw SQL
        // to bypass the repository's auto-fill).
        await dropGlossaryFtsTriggersForTest(db);
        await db.customStatement('DROP TABLE dictionary_entries_fts');
        await db.customStatement(
          'CREATE VIRTUAL TABLE dictionary_entries_fts USING fts5('
          'glossaries, content=dictionary_entries, content_rowid=id, '
          "tokenize='porter unicode61')",
        );

        await db.customInsert(
          'INSERT INTO dictionary_entries '
          '(expression, reading, glossaries, dictionary_id) '
          'VALUES (?, ?, ?, ?)',
          variables: [
            Variable.withString('学校'),
            Variable.withString('がっこう'),
            Variable.withString(structured(['school'])),
            Variable.withInt(dictId),
          ],
        );
        await db.customStatement(
          "INSERT INTO dictionary_entries_fts(dictionary_entries_fts) "
          "VALUES ('rebuild')",
        );

        // The open-time shape fix swaps the index; the deferred startup
        // job fills search_text for the pre-existing rows.
        await db.ensureGlossaryFtsForTesting();
        await db.backfillGlossarySearchText();

        final ftsSql =
            (await db
                    .customSelect(
                      "SELECT sql FROM sqlite_master "
                      "WHERE name = 'dictionary_entries_fts'",
                    )
                    .getSingle())
                .data['sql']
                .toString();
        expect(ftsSql, contains('search_text'));

        final backfilled =
            (await db
                    .customSelect(
                      'SELECT search_text FROM dictionary_entries '
                      "WHERE expression = '学校'",
                    )
                    .getSingle())
                .data['search_text'];
        expect(backfilled, 'school');

        final results = await queryService.glossarySearchWithSource('school');
        expect(results.map((r) => r.entry.expression), contains('学校'));
      },
    );

    test('the current index shape is left untouched on reopen', () async {
      await repo.batchInsertEntries([entry('食べる', 'たべる', 'to eat')]);
      await db.ensureGlossaryFtsForTesting();

      final results = await queryService.glossarySearchWithSource('eat');
      expect(results.map((r) => r.entry.expression), contains('食べる'));
    });
  });
}
