import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  test(
    'migrates dictionary entries to schema version 15 without data loss',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'mekuru_migration_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final dbFile = File('${tempDir.path}/mekuru.sqlite');

      final seedDb = AppDatabase(NativeDatabase(dbFile));
      final repo = DictionaryRepository(seedDb);
      final dictionaryId = await repo.insertDictionary('TestDict');
      await repo.batchInsertEntries([
        DictionaryEntriesCompanion.insert(
          expression: '食べる',
          reading: const Value('たべる'),
          glossaries: '["to eat"]',
          dictionaryId: dictionaryId,
        ),
      ]);
      await seedDb.close();

      final legacyDb = sqlite.sqlite3.open(dbFile.path);
      legacyDb.execute('PRAGMA user_version = 14;');
      legacyDb.execute(
        'ALTER TABLE dictionary_entries RENAME TO dictionary_entries_old;',
      );
      legacyDb.execute('''
      CREATE TABLE dictionary_entries (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        expression TEXT NOT NULL,
        reading TEXT NOT NULL DEFAULT '',
        entry_kind TEXT NOT NULL DEFAULT 'regular',
        kanji_onyomi TEXT NOT NULL DEFAULT '',
        kanji_kunyomi TEXT NOT NULL DEFAULT '',
        glossaries TEXT NOT NULL,
        dictionary_id INTEGER NOT NULL
      );
    ''');
      legacyDb.execute('''
      INSERT INTO dictionary_entries (
        id,
        expression,
        reading,
        entry_kind,
        kanji_onyomi,
        kanji_kunyomi,
        glossaries,
        dictionary_id
      )
      SELECT
        id,
        expression,
        reading,
        entry_kind,
        kanji_onyomi,
        kanji_kunyomi,
        glossaries,
        dictionary_id
      FROM dictionary_entries_old;
    ''');
      legacyDb.execute('DROP TABLE dictionary_entries_old;');
      legacyDb.execute(
        'CREATE INDEX idx_expression ON dictionary_entries (expression);',
      );
      legacyDb.execute(
        'CREATE INDEX idx_reading ON dictionary_entries (reading);',
      );
      legacyDb.execute(
        'CREATE INDEX idx_expr_dictid ON dictionary_entries (expression, dictionary_id);',
      );
      legacyDb.execute(
        'CREATE INDEX idx_read_dictid ON dictionary_entries (reading, dictionary_id);',
      );
      legacyDb.close();

      final migratedDb = AppDatabase(NativeDatabase(dbFile));
      addTearDown(migratedDb.close);

      final entries = await migratedDb
          .select(migratedDb.dictionaryEntries)
          .get();
      expect(entries, hasLength(1));
      expect(entries.single.expression, '食べる');
      expect(entries.single.reading, 'たべる');
      expect(entries.single.glossaries, '["to eat"]');
      expect(entries.single.definitionTags, isEmpty);
      expect(entries.single.rules, isEmpty);
      expect(entries.single.termTags, isEmpty);
      expect(migratedDb.schemaVersion, 22);
    },
  );

  test(
    'repairs missing dictionary entry columns when user_version is already 15',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'mekuru_schema_repair_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final dbFile = File('${tempDir.path}/mekuru.sqlite');

      final seedDb = AppDatabase(NativeDatabase(dbFile));
      final repo = DictionaryRepository(seedDb);
      final dictionaryId = await repo.insertDictionary('RepairDict');
      await repo.batchInsertEntries([
        DictionaryEntriesCompanion.insert(
          expression: '食べる',
          reading: const Value('たべる'),
          glossaries: '["to eat"]',
          dictionaryId: dictionaryId,
        ),
      ]);
      await seedDb.close();

      final brokenDb = sqlite.sqlite3.open(dbFile.path);
      brokenDb.execute('PRAGMA user_version = 15;');
      brokenDb.execute(
        'ALTER TABLE dictionary_entries RENAME TO dictionary_entries_old;',
      );
      brokenDb.execute('''
      CREATE TABLE dictionary_entries (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        expression TEXT NOT NULL,
        reading TEXT NOT NULL DEFAULT '',
        glossaries TEXT NOT NULL,
        dictionary_id INTEGER NOT NULL
      );
    ''');
      brokenDb.execute('''
      INSERT INTO dictionary_entries (
        id,
        expression,
        reading,
        glossaries,
        dictionary_id
      )
      SELECT
        id,
        expression,
        reading,
        glossaries,
        dictionary_id
      FROM dictionary_entries_old;
    ''');
      brokenDb.execute('DROP TABLE dictionary_entries_old;');
      brokenDb.close();

      final repairedDb = AppDatabase(NativeDatabase(dbFile));
      addTearDown(repairedDb.close);
      final repairedRepo = DictionaryRepository(repairedDb);

      final entries = await repairedDb
          .select(repairedDb.dictionaryEntries)
          .get();
      expect(entries, hasLength(1));
      expect(entries.single.expression, '食べる');
      expect(entries.single.definitionTags, isEmpty);
      expect(entries.single.rules, isEmpty);
      expect(entries.single.termTags, isEmpty);

      await repairedRepo.batchInsertEntries([
        DictionaryEntriesCompanion.insert(
          expression: '飲む',
          reading: const Value('のむ'),
          definitionTags: const Value('v5'),
          rules: const Value('vi'),
          termTags: const Value('P'),
          glossaries: '["to drink"]',
          dictionaryId: dictionaryId,
        ),
      ]);

      final repairedEntries = await repairedDb
          .select(repairedDb.dictionaryEntries)
          .get();
      expect(repairedEntries, hasLength(2));
    },
  );

  test(
    'adds the pitch expression+dictionary index when migrating to schema 16',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'mekuru_pitch_index_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final dbFile = File('${tempDir.path}/mekuru.sqlite');

      final seedDb = AppDatabase(NativeDatabase(dbFile));
      final repo = DictionaryRepository(seedDb);
      final dictionaryId = await repo.insertDictionary('PitchDict');
      await seedDb
          .into(seedDb.pitchAccents)
          .insert(
            PitchAccentsCompanion.insert(
              expression: '食べる',
              reading: const Value('たべる'),
              downstepPosition: 2,
              dictionaryId: dictionaryId,
            ),
          );
      await seedDb.close();

      final legacyDb = sqlite.sqlite3.open(dbFile.path);
      legacyDb.execute('PRAGMA user_version = 15;');
      legacyDb.execute('DROP INDEX IF EXISTS idx_pitch_expr_dictid;');
      legacyDb.close();

      final migratedDb = AppDatabase(NativeDatabase(dbFile));
      addTearDown(migratedDb.close);

      final indexRows = await migratedDb
          .customSelect("PRAGMA index_list('pitch_accents')")
          .get();
      final indexNames = indexRows
          .map((row) => row.data['name']?.toString())
          .whereType<String>()
          .toSet();

      expect(indexNames, contains('idx_pitch_expr_dictid'));
      expect(migratedDb.schemaVersion, 22);
    },
  );

  test(
    'backfills word_events from saved_words when migrating to schema 19',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'mekuru_word_events_backfill_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final dbFile = File('${tempDir.path}/mekuru.sqlite');

      final firstSavedAt = DateTime(2024, 3, 4, 5, 6, 7);
      final secondSavedAt = DateTime(2024, 5, 6, 7, 8, 9);

      final seedDb = AppDatabase(NativeDatabase(dbFile));
      await seedDb
          .into(seedDb.savedWords)
          .insert(
            SavedWordsCompanion.insert(
              expression: '食べる',
              reading: const Value('たべる'),
              glossaries: '["to eat"]',
              dateAdded: Value(firstSavedAt),
            ),
          );
      await seedDb
          .into(seedDb.savedWords)
          .insert(
            SavedWordsCompanion.insert(
              expression: '飲む',
              reading: const Value('のむ'),
              glossaries: '["to drink"]',
              dateAdded: Value(secondSavedAt),
            ),
          );
      await seedDb.close();

      // Rewind to the pre-stats schema: v18 had neither stats table.
      final legacyDb = sqlite.sqlite3.open(dbFile.path);
      legacyDb.execute('PRAGMA user_version = 18;');
      legacyDb.execute('DROP TABLE IF EXISTS word_events;');
      legacyDb.execute('DROP TABLE IF EXISTS reading_sessions;');
      legacyDb.close();

      final migratedDb = AppDatabase(NativeDatabase(dbFile));
      addTearDown(migratedDb.close);

      final events = await (migratedDb.select(
        migratedDb.wordEvents,
      )..orderBy([(t) => OrderingTerm(expression: t.createdAt)])).get();

      expect(events, hasLength(2));
      expect(events.map((e) => e.expression), ['食べる', '飲む']);
      expect(events.every((e) => e.kind == 'saved'), isTrue);
      expect(events.every((e) => e.source == 'other'), isTrue);
      expect(events.first.createdAt, firstSavedAt);
      expect(events.last.createdAt, secondSavedAt);

      final sessionCount = await migratedDb
          .customSelect('SELECT COUNT(*) AS c FROM reading_sessions')
          .getSingle();
      expect(sessionCount.data['c'], 0);

      expect(migratedDb.schemaVersion, 22);
    },
  );

  test(
    'adds has_vertical_css and repairs primary_writing_mode at schema 20',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'mekuru_vertical_css_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final dbFile = File('${tempDir.path}/mekuru.sqlite');

      final seedDb = AppDatabase(NativeDatabase(dbFile));
      await seedDb
          .into(seedDb.books)
          .insert(
            BooksCompanion.insert(title: '吾輩は猫である', filePath: '/books/neko'),
          );
      await seedDb.close();

      // Rewind to v19 and also drop primary_writing_mode to simulate a
      // database that predates the (migration-less) schema-9-era column.
      // Both columns come back via the beforeOpen repair pass
      // (_booksRepairColumns), not a versioned migration block.
      final legacyDb = sqlite.sqlite3.open(dbFile.path);
      legacyDb.execute('PRAGMA user_version = 19;');
      legacyDb.execute('ALTER TABLE books DROP COLUMN has_vertical_css;');
      legacyDb.execute('ALTER TABLE books DROP COLUMN primary_writing_mode;');
      legacyDb.close();

      final migratedDb = AppDatabase(NativeDatabase(dbFile));
      addTearDown(migratedDb.close);

      final book = await migratedDb.select(migratedDb.books).getSingle();
      expect(book.title, '吾輩は猫である');
      expect(book.hasVerticalCss, null);
      expect(book.primaryWritingMode, null);

      // Both columns must be insertable after the migration.
      await migratedDb
          .into(migratedDb.books)
          .insert(
            BooksCompanion.insert(
              title: '坊っちゃん',
              filePath: '/books/botchan',
              primaryWritingMode: const Value('vertical-rl'),
              hasVerticalCss: const Value(true),
            ),
          );

      expect(migratedDb.schemaVersion, 22);
    },
  );

  test('creates collections tables when migrating to schema 21', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'mekuru_collections_',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final dbFile = File('${tempDir.path}/mekuru.sqlite');

    final seedDb = AppDatabase(NativeDatabase(dbFile));
    await seedDb
        .into(seedDb.books)
        .insert(
          BooksCompanion.insert(title: '吾輩は猫である', filePath: '/books/neko'),
        );
    await seedDb.close();

    // Rewind to v20: drop the collections tables (no-ops on a database that
    // predates them).
    final legacyDb = sqlite.sqlite3.open(dbFile.path);
    legacyDb.execute('PRAGMA user_version = 20;');
    legacyDb.execute('DROP TABLE IF EXISTS book_collections;');
    legacyDb.execute('DROP TABLE IF EXISTS collections;');
    legacyDb.close();

    final migratedDb = AppDatabase(NativeDatabase(dbFile));
    addTearDown(migratedDb.close);

    await migratedDb.customStatement(
      "INSERT INTO collections (name) VALUES ('Novels')",
    );
    await migratedDb.customStatement(
      'INSERT INTO book_collections (book_id, collection_id) VALUES (1, 1)',
    );
    final memberCount = await migratedDb
        .customSelect('SELECT COUNT(*) AS c FROM book_collections')
        .getSingle();
    expect(memberCount.data['c'], 1);
    expect(migratedDb.schemaVersion, 22);
  });

  test('adds book_collections.position when migrating to schema 22', () async {
    final tempDir = await Directory.systemTemp.createTemp('mekuru_position_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final dbFile = File('${tempDir.path}/mekuru.sqlite');

    final seedDb = AppDatabase(NativeDatabase(dbFile));
    await seedDb
        .into(seedDb.books)
        .insert(
          BooksCompanion.insert(title: '吾輩は猫である', filePath: '/books/neko'),
        );
    await seedDb.close();

    // Rewind to v21: recreate book_collections without the position column,
    // exactly as a v21 install (the parallel test build) has it.
    final legacyDb = sqlite.sqlite3.open(dbFile.path);
    legacyDb.execute('PRAGMA user_version = 21;');
    legacyDb.execute('DROP TABLE book_collections;');
    legacyDb.execute('''
      CREATE TABLE book_collections (
        book_id INTEGER NOT NULL,
        collection_id INTEGER NOT NULL,
        PRIMARY KEY (book_id, collection_id)
      );
    ''');
    legacyDb.execute("INSERT INTO collections (name) VALUES ('Novels');");
    legacyDb.execute(
      'INSERT INTO book_collections (book_id, collection_id) VALUES (1, 1);',
    );
    legacyDb.close();

    final migratedDb = AppDatabase(NativeDatabase(dbFile));
    addTearDown(migratedDb.close);

    // The pre-existing membership survives and reads position 0.
    final row = await migratedDb
        .customSelect('SELECT position FROM book_collections')
        .getSingle();
    expect(row.data['position'], 0);
    expect(migratedDb.schemaVersion, 22);
  });
}
