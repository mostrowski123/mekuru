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
      legacyDb.dispose();

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
      expect(migratedDb.schemaVersion, 15);
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
      brokenDb.dispose();

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
}
