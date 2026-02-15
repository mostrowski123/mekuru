import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_importer.dart';

/// Creates an in-memory Drift database for testing.
AppDatabase createTestDatabase() {
  return AppDatabase(NativeDatabase.memory());
}

/// Creates a temporary Yomitan-format zip file for testing.
Future<String> createTestYomitanZip({
  String dictionaryName = 'Test Dictionary',
  List<List<dynamic>>? entries,
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
  final tempFiles = <String>[];

  setUp(() {
    db = createTestDatabase();
    repo = DictionaryRepository(db);
    importer = DictionaryImporter(repo);
  });

  tearDown(() async {
    await db.close();
    // Clean up temp files
    for (final path in tempFiles) {
      final dir = Directory(path).parent;
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    }
    tempFiles.clear();
  });

  group('DictionaryImporter — importFromFile', () {
    test(
      'imports a valid Yomitan zip and creates dictionary + entries',
      () async {
        final zipPath = await createTestYomitanZip();
        tempFiles.add(zipPath);

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
      tempFiles.add(zipPath);

      await importer.importFromFile(zipPath);

      final allEntries = await db.select(db.dictionaryEntries).get();
      expect(allEntries, hasLength(1));
      expect(allEntries.first.expression, '漢字');
      expect(allEntries.first.reading, 'かんじ');

      final glossaries = jsonDecode(allEntries.first.glossaries) as List;
      expect(glossaries, ['Chinese character']);
    });

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
      tempFiles.add(zipPath);

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
      tempFiles.add(zipPath);

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
      tempFiles.add(zipPath);

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
      tempFiles.add(zipPath);

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
      tempFiles.add(zipPath);

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
      tempFiles.add(zipPath);

      final count = await importer.importFromFile(zipPath);

      // Should import entries from both banks
      expect(count, 2);
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
      tempFiles.add(zipPath);

      await importer.importFromFile(zipPath);

      final dicts = await repo.getAllDictionaries();
      expect(dicts.first.name, 'Unknown Dictionary');
    });
  });
}
