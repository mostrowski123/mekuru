import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/models/dictionary_entry.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_importer.dart';

/// Creates an in-memory Drift database for testing.
AppDatabase createTestDatabase() {
  return AppDatabase(NativeDatabase.memory());
}

class _ThrowingDictionaryRepository extends DictionaryRepository {
  _ThrowingDictionaryRepository(super.db, {this.throwOnPitchInsert = false});

  final bool throwOnPitchInsert;
  bool _hasThrown = false;

  @override
  Future<int> batchInsertPitchAccents(
    List<PitchAccentsCompanion> entries, {
    int batchSize = 10000,
  }) async {
    if (throwOnPitchInsert && !_hasThrown && entries.isNotEmpty) {
      _hasThrown = true;
      throw StateError('forced pitch insert failure');
    }
    return super.batchInsertPitchAccents(entries, batchSize: batchSize);
  }
}

/// Creates a temporary Yomitan-format zip file for testing.
Future<String> createTestYomitanZip({
  String dictionaryName = 'Test Dictionary',
  List<List<dynamic>>? entries,
  List<List<dynamic>>? kanjiEntries,
  List<List<dynamic>>? termMetaEntries,
}) async {
  entries ??= [
    [
      '食べる',
      'たべる',
      '',
      '',
      0,
      ['to eat', 'to consume'],
      1,
      '',
    ],
    [
      '飲む',
      'のむ',
      '',
      '',
      0,
      ['to drink'],
      2,
      '',
    ],
    [
      '走る',
      'はしる',
      '',
      '',
      0,
      ['to run'],
      3,
      '',
    ],
  ];

  final archive = Archive();

  // index.json
  final indexContent = utf8.encode(
    jsonEncode({'title': dictionaryName, 'format': 3, 'revision': '1.0'}),
  );
  archive.addFile(ArchiveFile('index.json', indexContent.length, indexContent));

  // term_bank_1.json
  final termBankContent = utf8.encode(jsonEncode(entries));
  archive.addFile(
    ArchiveFile('term_bank_1.json', termBankContent.length, termBankContent),
  );

  if (kanjiEntries != null) {
    final kanjiBankContent = utf8.encode(jsonEncode(kanjiEntries));
    archive.addFile(
      ArchiveFile(
        'kanji_bank_1.json',
        kanjiBankContent.length,
        kanjiBankContent,
      ),
    );
  }

  if (termMetaEntries != null) {
    final termMetaContent = utf8.encode(jsonEncode(termMetaEntries));
    archive.addFile(
      ArchiveFile(
        'term_meta_bank_1.json',
        termMetaContent.length,
        termMetaContent,
      ),
    );
  }

  // Write to temp file
  final tempDir = await Directory.systemTemp.createTemp('yomitan_test_');
  final zipPath = '${tempDir.path}/test_dict.zip';
  final zipBytes = ZipEncoder().encode(archive);
  await File(zipPath).writeAsBytes(zipBytes);

  return zipPath;
}

void main() {
  late AppDatabase db;
  late DictionaryRepository repo;
  late DictionaryImporter importer;
  final tempDirs = <String>{};

  void trackTempFile(String path) {
    tempDirs.add(File(path).parent.path);
  }

  setUp(() {
    db = createTestDatabase();
    repo = DictionaryRepository(db);
    importer = DictionaryImporter(repo);
  });

  tearDown(() async {
    await db.close();
    // Clean up temp files
    for (final path in tempDirs) {
      final dir = Directory(path);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    }
    tempDirs.clear();
  });

  group('DictionaryImporter — importFromFile', () {
    test(
      'imports a valid Yomitan zip and creates dictionary + entries',
      () async {
        final zipPath = await createTestYomitanZip();
        trackTempFile(zipPath);

        final count = await importer.importFromFile(zipPath);

        expect(count, 3);

        // Verify dictionary was created
        final dicts = await repo.getAllDictionaries();
        expect(dicts, hasLength(1));
        expect(dicts.first.name, 'Test Dictionary');
        expect(dicts.first.isEnabled, isTrue);

        // Verify entries
        expect(await repo.getEntryCount(dicts.first.id), 3);
      },
    );

    test('parses expression and reading correctly', () async {
      final zipPath = await createTestYomitanZip(
        entries: [
          [
            '漢字',
            'かんじ',
            '',
            '',
            0,
            ['Chinese character'],
            1,
            '',
          ],
        ],
      );
      trackTempFile(zipPath);

      await importer.importFromFile(zipPath);

      final allEntries = await db.select(db.dictionaryEntries).get();
      expect(allEntries, hasLength(1));
      expect(allEntries.first.expression, '漢字');
      expect(allEntries.first.reading, 'かんじ');
      expect(allEntries.first.entryKind, DictionaryEntryKinds.regular);
      expect(allEntries.first.kanjiOnyomi, isEmpty);
      expect(allEntries.first.kanjiKunyomi, isEmpty);
      expect(allEntries.first.definitionTags, isEmpty);
      expect(allEntries.first.rules, isEmpty);
      expect(allEntries.first.termTags, isEmpty);

      final glossaries = jsonDecode(allEntries.first.glossaries) as List;
      expect(glossaries, ['Chinese character']);
    });

    test('stores part of speech fields from Yomitan term rows', () async {
      final zipPath = await createTestYomitanZip(
        entries: [
          [
            '食べる',
            'たべる',
            'v1',
            'vt',
            0,
            ['to eat'],
            1,
            'P',
          ],
        ],
      );
      trackTempFile(zipPath);

      await importer.importFromFile(zipPath);

      final allEntries = await db.select(db.dictionaryEntries).get();
      expect(allEntries, hasLength(1));
      expect(allEntries.first.definitionTags, 'v1');
      expect(allEntries.first.rules, 'vt');
      expect(allEntries.first.termTags, 'P');
    });

    test(
      'stores kanji metadata for kanji_bank entries used by KANJIDIC downloads',
      () async {
        final zipPath = await createTestYomitanZip(
          dictionaryName: 'KANJIDIC English',
          entries: [],
          kanjiEntries: [
            [
              '日',
              'ニチ ジツ',
              'ひ か',
              '',
              ['sun', 'day'],
            ],
          ],
        );
        trackTempFile(zipPath);

        final count = await importer.importFromFile(zipPath);

        expect(count, 1);

        final allEntries = await db.select(db.dictionaryEntries).get();
        expect(allEntries, hasLength(1));

        final entry = allEntries.single;
        expect(entry.expression, '日');
        expect(entry.reading, 'ニチ ジツ ひ か');
        expect(entry.entryKind, DictionaryEntryKinds.kanji);
        expect(jsonDecode(entry.kanjiOnyomi), ['ニチ', 'ジツ']);
        expect(jsonDecode(entry.kanjiKunyomi), ['ひ', 'か']);
      },
    );

    test('handles complex glossary objects', () async {
      final zipPath = await createTestYomitanZip(
        entries: [
          [
            '例',
            'れい',
            '',
            '',
            0,
            [
              'example',
              {'type': 'structured', 'content': 'detailed meaning'},
            ],
            1,
            '',
          ],
        ],
      );
      trackTempFile(zipPath);

      await importer.importFromFile(zipPath);

      final allEntries = await db.select(db.dictionaryEntries).get();
      final glossaries = jsonDecode(allEntries.first.glossaries) as List;
      expect(glossaries, hasLength(2));
      expect(glossaries[0], 'example');
      // Complex object should be JSON-encoded
      expect(glossaries[1], contains('structured'));
    });

    test('extracts dictionary name from index.json', () async {
      final zipPath = await createTestYomitanZip(
        dictionaryName: 'JMdict English',
      );
      trackTempFile(zipPath);

      await importer.importFromFile(zipPath);

      final dicts = await repo.getAllDictionaries();
      expect(dicts.first.name, 'JMdict English');
    });

    test('reports progress during import', () async {
      final entries = List.generate(
        25,
        (i) => [
          'word_$i',
          'reading_$i',
          '',
          '',
          0,
          ['meaning_$i'],
          i,
          '',
        ],
      );

      final zipPath = await createTestYomitanZip(entries: entries);
      trackTempFile(zipPath);

      final progressUpdates = <(int, int)>[];
      await importer.importFromFile(
        zipPath,
        onProgress: (processed, total) {
          progressUpdates.add((processed, total));
        },
      );

      // Should have at least 1 progress update
      expect(progressUpdates, isNotEmpty);
      // Final update should show all entries processed
      expect(progressUpdates.last.$1, 25);
      expect(progressUpdates.last.$2, 25);
    });

    test('throws FileSystemException for non-existent file', () async {
      expect(
        () => importer.importFromFile('/nonexistent/path.zip'),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('skips entries with empty expression', () async {
      final zipPath = await createTestYomitanZip(
        entries: [
          [
            '',
            'reading',
            '',
            '',
            0,
            ['meaning'],
            1,
            '',
          ],
          [
            '食べる',
            'たべる',
            '',
            '',
            0,
            ['to eat'],
            2,
            '',
          ],
        ],
      );
      trackTempFile(zipPath);

      final count = await importer.importFromFile(zipPath);
      // Only the non-empty expression should be imported
      expect(count, 1);
    });

    test('skips malformed entries with insufficient fields', () async {
      final zipPath = await createTestYomitanZip(
        entries: [
          ['only', 'three', 'fields'], // Too few fields
          [
            '食べる',
            'たべる',
            '',
            '',
            0,
            ['to eat'],
            2,
            '',
          ],
        ],
      );
      trackTempFile(zipPath);

      final count = await importer.importFromFile(zipPath);
      expect(count, 1);
    });

    test('handles multiple term_bank files', () async {
      // Create a zip with two term bank files
      final archive = Archive();

      final indexContent = utf8.encode(
        jsonEncode({'title': 'Multi Bank Dict', 'format': 3}),
      );
      archive.addFile(
        ArchiveFile('index.json', indexContent.length, indexContent),
      );

      final bank1 = utf8.encode(
        jsonEncode([
          [
            '食べる',
            'たべる',
            '',
            '',
            0,
            ['to eat'],
            1,
            '',
          ],
        ]),
      );
      archive.addFile(ArchiveFile('term_bank_1.json', bank1.length, bank1));

      final bank2 = utf8.encode(
        jsonEncode([
          [
            '飲む',
            'のむ',
            '',
            '',
            0,
            ['to drink'],
            2,
            '',
          ],
        ]),
      );
      archive.addFile(ArchiveFile('term_bank_2.json', bank2.length, bank2));

      final tempDir = await Directory.systemTemp.createTemp('yomitan_multi_');
      final zipPath = '${tempDir.path}/multi_dict.zip';
      await File(zipPath).writeAsBytes(ZipEncoder().encode(archive));
      trackTempFile(zipPath);

      final count = await importer.importFromFile(zipPath);

      // Should import entries from both banks
      expect(count, 2);
    });

    test('imports kana-only and reading-specific frequency rows', () async {
      final zipPath = await createTestYomitanZip(
        termMetaEntries: [
          [
            '私',
            'freq',
            {
              'reading': 'わたし',
              'frequency': {'value': 32, 'displayValue': '32'},
            },
          ],
          [
            'わっし',
            'freq',
            {'value': 40276, 'displayValue': '40276㋕'},
          ],
        ],
      );
      trackTempFile(zipPath);

      await importer.importFromFile(zipPath);

      final frequencies = await db.select(db.frequencies).get();
      expect(
        frequencies.any(
          (f) =>
              f.expression == '私' &&
              f.reading == 'わたし' &&
              f.frequencyRank == 32,
        ),
        isTrue,
      );
      expect(
        frequencies.any(
          (f) =>
              f.expression == 'わっし' &&
              f.reading.isEmpty &&
              f.frequencyRank == 40276,
        ),
        isTrue,
      );
    });

    test('rolls back a zip import when a later batch insert fails', () async {
      final rollbackDb = createTestDatabase();
      addTearDown(rollbackDb.close);
      final rollbackRepo = _ThrowingDictionaryRepository(
        rollbackDb,
        throwOnPitchInsert: true,
      );
      final rollbackImporter = DictionaryImporter(rollbackRepo);

      final zipPath = await createTestYomitanZip(
        dictionaryName: 'Rollback Zip',
        termMetaEntries: [
          [
            '食べる',
            'pitch',
            {
              'reading': 'たべる',
              'pitches': [
                {'position': 2},
              ],
            },
          ],
        ],
      );
      trackTempFile(zipPath);

      await expectLater(
        rollbackImporter.importFromFile(zipPath),
        throwsA(isA<StateError>()),
      );

      expect(await rollbackRepo.getAllDictionaries(), isEmpty);
      expect(
        await rollbackDb.select(rollbackDb.dictionaryEntries).get(),
        isEmpty,
      );
      expect(await rollbackDb.select(rollbackDb.pitchAccents).get(), isEmpty);
    });
  });

  group('DictionaryImporter — missing index.json', () {
    test('uses fallback name when index.json is missing', () async {
      final archive = Archive();
      final bankContent = utf8.encode(
        jsonEncode([
          [
            '食べる',
            'たべる',
            '',
            '',
            0,
            ['to eat'],
            1,
            '',
          ],
        ]),
      );
      archive.addFile(
        ArchiveFile('term_bank_1.json', bankContent.length, bankContent),
      );

      final tempDir = await Directory.systemTemp.createTemp('yomitan_noindex_');
      final zipPath = '${tempDir.path}/no_index.zip';
      await File(zipPath).writeAsBytes(ZipEncoder().encode(archive));
      trackTempFile(zipPath);

      await importer.importFromFile(zipPath);

      final dicts = await repo.getAllDictionaries();
      expect(dicts.first.name, 'Unknown Dictionary');
    });
  });

  // ══════════════════════════════════════════════════════════════════
  //  Collection import tests
  // ══════════════════════════════════════════════════════════════════

  group('DictionaryImporter — importCollectionFromFile', () {
    /// Builds a minimal Dexie collection JSON string.
    String buildCollectionJson(
      Map<String, List<(String, String, List<String>)>> dictEntries,
    ) {
      final rows = <Map<String, dynamic>>[];
      var id = 1;
      for (final entry in dictEntries.entries) {
        for (final term in entry.value) {
          rows.add({
            'expression': term.$1,
            'reading': term.$2,
            'glossary': term.$3,
            'dictionary': entry.key,
            'id': id++,
          });
        }
      }
      return jsonEncode({
        'formatName': 'dexie',
        'formatVersion': 1,
        'data': {
          'databaseName': 'dict',
          'tables': [
            {'name': 'terms', 'schema': '++id', 'rowCount': rows.length},
          ],
          'data': [
            {'tableName': 'terms', 'inbound': true, 'rows': rows},
          ],
        },
      });
    }

    Future<String> writeCollectionFile(String content) async {
      final dir = await Directory.systemTemp.createTemp('dict_coll_test_');
      final file = File('${dir.path}/collection.json');
      await file.writeAsString(content);
      trackTempFile(file.path);
      return file.path;
    }

    test('imports multiple dictionaries from collection', () async {
      final json = buildCollectionJson({
        'JMdict': [
          ('食べる', 'たべる', ['to eat']),
          ('飲む', 'のむ', ['to drink']),
        ],
        'JMnedict': [
          ('東京', 'とうきょう', ['Tokyo']),
        ],
      });
      final filePath = await writeCollectionFile(json);

      final result = await importer.importCollectionFromFile(filePath);

      expect(result.importedDictionaries, ['JMdict', 'JMnedict']);
      expect(result.skippedDictionaries, isEmpty);
      expect(result.totalEntriesImported, 3);

      final dicts = await repo.getAllDictionaries();
      expect(dicts.map((d) => d.name).toSet(), {'JMdict', 'JMnedict'});
    });

    test('entries are assigned to correct dictionary IDs', () async {
      final json = buildCollectionJson({
        'DictA': [
          ('猫', 'ねこ', ['cat']),
        ],
        'DictB': [
          ('犬', 'いぬ', ['dog']),
        ],
      });
      final filePath = await writeCollectionFile(json);

      await importer.importCollectionFromFile(filePath);

      final dicts = await repo.getAllDictionaries();
      final dictA = dicts.firstWhere((d) => d.name == 'DictA');
      final dictB = dicts.firstWhere((d) => d.name == 'DictB');

      expect(await repo.getEntryCount(dictA.id), 1);
      expect(await repo.getEntryCount(dictB.id), 1);
    });

    test('skips dictionaries that already exist by name', () async {
      await repo.insertDictionary('JMdict');

      final json = buildCollectionJson({
        'JMdict': [
          ('食べる', 'たべる', ['to eat']),
        ],
        'NewDict': [
          ('走る', 'はしる', ['to run']),
        ],
      });
      final filePath = await writeCollectionFile(json);

      final skippedNames = <String>[];
      final result = await importer.importCollectionFromFile(
        filePath,
        onDictionarySkipped: (name) => skippedNames.add(name),
      );

      expect(result.importedDictionaries, ['NewDict']);
      expect(result.skippedDictionaries, ['JMdict']);
      expect(skippedNames, ['JMdict']);
      expect(result.totalEntriesImported, 1);
    });

    test('parses expression, reading, and glossary correctly', () async {
      final json = buildCollectionJson({
        'TestDict': [
          ('食べる', 'たべる', ['to eat', 'to consume']),
        ],
      });
      final filePath = await writeCollectionFile(json);

      await importer.importCollectionFromFile(filePath);

      final dicts = await repo.getAllDictionaries();
      final dict = dicts.firstWhere((d) => d.name == 'TestDict');

      final entries = await (db.select(
        db.dictionaryEntries,
      )..where((t) => t.dictionaryId.equals(dict.id))).get();

      expect(entries, hasLength(1));
      expect(entries.first.expression, '食べる');
      expect(entries.first.reading, 'たべる');
      expect(entries.first.definitionTags, isEmpty);
      expect(entries.first.rules, isEmpty);
      expect(entries.first.termTags, isEmpty);
      expect(jsonDecode(entries.first.glossaries), ['to eat', 'to consume']);
    });

    test('stores part of speech fields from collection term rows', () async {
      final rows = [
        {
          'expression': '食べる',
          'reading': 'たべる',
          'definitionTags': 'v1',
          'rules': 'vt',
          'termTags': 'P',
          'glossary': ['to eat'],
          'dictionary': 'TaggedDict',
          'id': 1,
        },
      ];
      final jsonStr = jsonEncode({
        'formatName': 'dexie',
        'formatVersion': 1,
        'data': {
          'databaseName': 'dict',
          'tables': [
            {'name': 'terms', 'schema': '++id', 'rowCount': 1},
          ],
          'data': [
            {'tableName': 'terms', 'inbound': true, 'rows': rows},
          ],
        },
      });
      final filePath = await writeCollectionFile(jsonStr);

      await importer.importCollectionFromFile(filePath);

      final dicts = await repo.getAllDictionaries();
      final dict = dicts.firstWhere((d) => d.name == 'TaggedDict');
      final entries = await (db.select(
        db.dictionaryEntries,
      )..where((t) => t.dictionaryId.equals(dict.id))).get();

      expect(entries, hasLength(1));
      expect(entries.first.definitionTags, 'v1');
      expect(entries.first.rules, 'vt');
      expect(entries.first.termTags, 'P');
    });

    test(
      'collection stores empty part of speech fields when tags are absent',
      () async {
        final rows = [
          {
            'expression': '走る',
            'reading': 'はしる',
            'glossary': ['to run'],
            'dictionary': 'PlainDict',
            'id': 1,
          },
        ];
        final jsonStr = jsonEncode({
          'formatName': 'dexie',
          'formatVersion': 1,
          'data': {
            'databaseName': 'dict',
            'tables': [
              {'name': 'terms', 'schema': '++id', 'rowCount': 1},
            ],
            'data': [
              {'tableName': 'terms', 'inbound': true, 'rows': rows},
            ],
          },
        });
        final filePath = await writeCollectionFile(jsonStr);

        await importer.importCollectionFromFile(filePath);

        final dicts = await repo.getAllDictionaries();
        final dict = dicts.firstWhere((d) => d.name == 'PlainDict');
        final entries = await (db.select(
          db.dictionaryEntries,
        )..where((t) => t.dictionaryId.equals(dict.id))).get();

        expect(entries, hasLength(1));
        expect(entries.first.definitionTags, isEmpty);
        expect(entries.first.rules, isEmpty);
        expect(entries.first.termTags, isEmpty);
      },
    );

    test('calls onDictionaryStart with correct parameters', () async {
      final json = buildCollectionJson({
        'DictA': [
          ('猫', 'ねこ', ['cat']),
          ('犬', 'いぬ', ['dog']),
        ],
        'DictB': [
          ('鳥', 'とり', ['bird']),
        ],
      });
      final filePath = await writeCollectionFile(json);

      final starts = <(String, int, int, int)>[];
      await importer.importCollectionFromFile(
        filePath,
        onDictionaryStart: (name, count, index, total) {
          starts.add((name, count, index, total));
        },
      );

      expect(starts, hasLength(2));
      expect(starts[0], ('DictA', 2, 0, 2));
      expect(starts[1], ('DictB', 1, 1, 2));
    });

    test('calls onProgress during batch insert', () async {
      final json = buildCollectionJson({
        'TestDict': [
          ('猫', 'ねこ', ['cat']),
          ('犬', 'いぬ', ['dog']),
          ('鳥', 'とり', ['bird']),
        ],
      });
      final filePath = await writeCollectionFile(json);

      final progressCalls = <(int, int)>[];
      await importer.importCollectionFromFile(
        filePath,
        onProgress: (processed, total) {
          progressCalls.add((processed, total));
        },
      );

      expect(progressCalls, isNotEmpty);
      expect(progressCalls.last.$1, progressCalls.last.$2);
    });

    test('handles empty collection', () async {
      final json = buildCollectionJson({});
      final filePath = await writeCollectionFile(json);

      final result = await importer.importCollectionFromFile(filePath);

      expect(result.importedDictionaries, isEmpty);
      expect(result.skippedDictionaries, isEmpty);
      expect(result.totalEntriesImported, 0);
    });

    test('skips all dictionaries when all already exist', () async {
      await repo.insertDictionary('DictA');
      await repo.insertDictionary('DictB');

      final json = buildCollectionJson({
        'DictA': [
          ('猫', 'ねこ', ['cat']),
        ],
        'DictB': [
          ('犬', 'いぬ', ['dog']),
        ],
      });
      final filePath = await writeCollectionFile(json);

      final result = await importer.importCollectionFromFile(filePath);

      expect(result.importedDictionaries, isEmpty);
      expect(result.skippedDictionaries, ['DictA', 'DictB']);
      expect(result.totalEntriesImported, 0);
    });

    test('throws for file not found', () async {
      expect(
        () => importer.importCollectionFromFile('/nonexistent/path.json'),
        throwsA(isA<FileSystemException>()),
      );
    });

    test(
      'rolls back a collection import when a later batch insert fails',
      () async {
        final rollbackDb = createTestDatabase();
        addTearDown(rollbackDb.close);
        final rollbackRepo = _ThrowingDictionaryRepository(
          rollbackDb,
          throwOnPitchInsert: true,
        );
        final rollbackImporter = DictionaryImporter(rollbackRepo);

        final jsonStr = jsonEncode({
          'formatName': 'dexie',
          'formatVersion': 1,
          'data': {
            'databaseName': 'dict',
            'tables': [
              {'name': 'terms', 'schema': '++id', 'rowCount': 1},
              {'name': 'termMeta', 'schema': '++id', 'rowCount': 1},
            ],
            'data': [
              {
                'tableName': 'terms',
                'inbound': true,
                'rows': [
                  {
                    'expression': '食べる',
                    'reading': 'たべる',
                    'glossary': ['to eat'],
                    'dictionary': 'Rollback Collection',
                    'id': 1,
                  },
                ],
              },
              {
                'tableName': 'termMeta',
                'inbound': true,
                'rows': [
                  {
                    'expression': '食べる',
                    'mode': 'pitch',
                    'dictionary': 'Rollback Collection',
                    'data': {
                      'reading': 'たべる',
                      'pitches': [
                        {'position': 2},
                      ],
                    },
                    'id': 2,
                  },
                ],
              },
            ],
          },
        });
        final filePath = await writeCollectionFile(jsonStr);

        await expectLater(
          rollbackImporter.importCollectionFromFile(filePath),
          throwsA(isA<StateError>()),
        );

        expect(await rollbackRepo.getAllDictionaries(), isEmpty);
        expect(
          await rollbackDb.select(rollbackDb.dictionaryEntries).get(),
          isEmpty,
        );
        expect(await rollbackDb.select(rollbackDb.pitchAccents).get(), isEmpty);
      },
    );

    test('handles glossary with structured objects', () async {
      final rows = [
        {
          'expression': '食べる',
          'reading': 'たべる',
          'glossary': [
            'to eat',
            {'type': 'structured-content', 'content': 'detailed'},
          ],
          'dictionary': 'StructuredDict',
          'id': 1,
        },
      ];
      final jsonStr = jsonEncode({
        'formatName': 'dexie',
        'formatVersion': 1,
        'data': {
          'databaseName': 'dict',
          'tables': [
            {'name': 'terms', 'schema': '++id', 'rowCount': 1},
          ],
          'data': [
            {'tableName': 'terms', 'inbound': true, 'rows': rows},
          ],
        },
      });
      final filePath = await writeCollectionFile(jsonStr);

      await importer.importCollectionFromFile(filePath);

      final dicts = await repo.getAllDictionaries();
      final dict = dicts.firstWhere((d) => d.name == 'StructuredDict');
      final entries = await (db.select(
        db.dictionaryEntries,
      )..where((t) => t.dictionaryId.equals(dict.id))).get();

      expect(entries, hasLength(1));
      final glossary = jsonDecode(entries.first.glossaries) as List;
      expect(glossary, hasLength(2));
      expect(glossary[0], 'to eat');
      expect(glossary[1], contains('structured-content'));
    });

    test('collection skips entries with empty expression', () async {
      final rows = [
        {
          'expression': '',
          'reading': 'reading',
          'glossary': ['meaning'],
          'dictionary': 'TestDict',
          'id': 1,
        },
        {
          'expression': '食べる',
          'reading': 'たべる',
          'glossary': ['to eat'],
          'dictionary': 'TestDict',
          'id': 2,
        },
      ];
      final jsonStr = jsonEncode({
        'formatName': 'dexie',
        'formatVersion': 1,
        'data': {
          'databaseName': 'dict',
          'tables': [
            {'name': 'terms', 'schema': '++id', 'rowCount': 2},
          ],
          'data': [
            {'tableName': 'terms', 'inbound': true, 'rows': rows},
          ],
        },
      });
      final filePath = await writeCollectionFile(jsonStr);

      final result = await importer.importCollectionFromFile(filePath);

      expect(result.totalEntriesImported, 1);
    });

    test('handles deeply nested structured-content glossary', () async {
      // Simulates dictionaries like NEW斎藤和英大辞典 that use deeply
      // nested structured-content with tags, styles, and child arrays.
      final rows = [
        {
          'expression': '試験',
          'reading': 'しけん',
          'glossary': [
            {
              'type': 'structured-content',
              'content': [
                'plain text',
                {
                  'tag': 'ul',
                  'content': [
                    {
                      'tag': 'li',
                      'style': {'fontWeight': 'bold'},
                      'content': 'definition one',
                    },
                    {'tag': 'li', 'content': 'definition two'},
                  ],
                },
              ],
            },
          ],
          'dictionary': 'DeepDict',
          'id': 1,
        },
      ];
      final jsonStr = jsonEncode({
        'formatName': 'dexie',
        'formatVersion': 1,
        'data': {
          'databaseName': 'dict',
          'tables': [
            {'name': 'terms', 'schema': '++id', 'rowCount': 1},
          ],
          'data': [
            {'tableName': 'terms', 'inbound': true, 'rows': rows},
          ],
        },
      });
      final filePath = await writeCollectionFile(jsonStr);

      await importer.importCollectionFromFile(filePath);

      final dicts = await repo.getAllDictionaries();
      final dict = dicts.firstWhere((d) => d.name == 'DeepDict');
      final entries = await (db.select(
        db.dictionaryEntries,
      )..where((t) => t.dictionaryId.equals(dict.id))).get();

      expect(entries, hasLength(1));
      final glossary = jsonDecode(entries.first.glossaries) as List;
      expect(glossary, hasLength(1));

      // The glossary item should be valid JSON that can be re-parsed
      final parsed = jsonDecode(glossary[0] as String) as Map<String, dynamic>;
      expect(parsed['type'], 'structured-content');
      expect(parsed['content'], isList);
      final content = parsed['content'] as List;
      expect(content[0], 'plain text');

      // Verify the nested ul/li structure survived round-trip
      final ul = content[1] as Map<String, dynamic>;
      expect(ul['tag'], 'ul');
      final liItems = ul['content'] as List;
      expect(liItems, hasLength(2));
      expect((liItems[0] as Map)['tag'], 'li');
      expect((liItems[0] as Map)['style'], {'fontWeight': 'bold'});
      expect((liItems[0] as Map)['content'], 'definition one');
      expect((liItems[1] as Map)['tag'], 'li');
      expect((liItems[1] as Map)['content'], 'definition two');
    });

    test(
      'handles glossary with multiple properties and nested arrays',
      () async {
        // Multiple top-level properties + nested array of mixed types
        final rows = [
          {
            'expression': '例',
            'reading': 'れい',
            'glossary': [
              {
                'type': 'structured-content',
                'style': {'fontSize': '14px', 'color': 'red'},
                'content': [
                  'text',
                  42,
                  true,
                  null,
                  {'tag': 'span', 'content': 'nested'},
                ],
              },
            ],
            'dictionary': 'MultiPropDict',
            'id': 1,
          },
        ];
        final jsonStr = jsonEncode({
          'formatName': 'dexie',
          'formatVersion': 1,
          'data': {
            'databaseName': 'dict',
            'tables': [
              {'name': 'terms', 'schema': '++id', 'rowCount': 1},
            ],
            'data': [
              {'tableName': 'terms', 'inbound': true, 'rows': rows},
            ],
          },
        });
        final filePath = await writeCollectionFile(jsonStr);

        await importer.importCollectionFromFile(filePath);

        final dicts = await repo.getAllDictionaries();
        final dict = dicts.firstWhere((d) => d.name == 'MultiPropDict');
        final entries = await (db.select(
          db.dictionaryEntries,
        )..where((t) => t.dictionaryId.equals(dict.id))).get();

        final glossary = jsonDecode(entries.first.glossaries) as List;
        final parsed =
            jsonDecode(glossary[0] as String) as Map<String, dynamic>;
        expect(parsed['type'], 'structured-content');
        expect(parsed['style'], {'fontSize': '14px', 'color': 'red'});
        final content = parsed['content'] as List;
        expect(content[0], 'text');
        expect(content[1], 42);
        expect(content[2], true);
        expect(content[3], null);
        expect((content[4] as Map)['tag'], 'span');
        expect((content[4] as Map)['content'], 'nested');
      },
    );

    test('handles mixed plain string and structured glossary items', () async {
      final rows = [
        {
          'expression': '混合',
          'reading': 'こんごう',
          'glossary': [
            'plain meaning',
            {'type': 'structured-content', 'content': 'rich meaning'},
            'another plain',
          ],
          'dictionary': 'MixedDict',
          'id': 1,
        },
      ];
      final jsonStr = jsonEncode({
        'formatName': 'dexie',
        'formatVersion': 1,
        'data': {
          'databaseName': 'dict',
          'tables': [
            {'name': 'terms', 'schema': '++id', 'rowCount': 1},
          ],
          'data': [
            {'tableName': 'terms', 'inbound': true, 'rows': rows},
          ],
        },
      });
      final filePath = await writeCollectionFile(jsonStr);

      await importer.importCollectionFromFile(filePath);

      final dicts = await repo.getAllDictionaries();
      final dict = dicts.firstWhere((d) => d.name == 'MixedDict');
      final entries = await (db.select(
        db.dictionaryEntries,
      )..where((t) => t.dictionaryId.equals(dict.id))).get();

      final glossary = jsonDecode(entries.first.glossaries) as List;
      expect(glossary, hasLength(3));
      expect(glossary[0], 'plain meaning');
      // Structured item should be valid JSON
      final parsed = jsonDecode(glossary[1] as String) as Map<String, dynamic>;
      expect(parsed['type'], 'structured-content');
      expect(parsed['content'], 'rich meaning');
      expect(glossary[2], 'another plain');
    });

    test(
      'handles glossary with boolean and numeric values in objects',
      () async {
        final rows = [
          {
            'expression': '数値',
            'reading': 'すうち',
            'glossary': [
              {
                'type': 'structured-content',
                'data': {'count': 5, 'active': true, 'label': null},
              },
            ],
            'dictionary': 'NumericDict',
            'id': 1,
          },
        ];
        final jsonStr = jsonEncode({
          'formatName': 'dexie',
          'formatVersion': 1,
          'data': {
            'databaseName': 'dict',
            'tables': [
              {'name': 'terms', 'schema': '++id', 'rowCount': 1},
            ],
            'data': [
              {'tableName': 'terms', 'inbound': true, 'rows': rows},
            ],
          },
        });
        final filePath = await writeCollectionFile(jsonStr);

        await importer.importCollectionFromFile(filePath);

        final dicts = await repo.getAllDictionaries();
        final dict = dicts.firstWhere((d) => d.name == 'NumericDict');
        final entries = await (db.select(
          db.dictionaryEntries,
        )..where((t) => t.dictionaryId.equals(dict.id))).get();

        final glossary = jsonDecode(entries.first.glossaries) as List;
        final parsed =
            jsonDecode(glossary[0] as String) as Map<String, dynamic>;
        expect(parsed['type'], 'structured-content');
        final data = parsed['data'] as Map<String, dynamic>;
        expect(data['count'], 5);
        expect(data['active'], true);
        expect(data['label'], null);
      },
    );
  });
}
