import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_importer.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_query_service.dart';

import 'shared/test_infrastructure.dart';

// Yomitan term rows are positional arrays:
// [expression, reading, definitionTags, rules, score, glossary, sequence, termTags]
const _entries = <List<Object>>[
  [
    '食べる',
    'たべる',
    'v1',
    'vt',
    0,
    ['to eat'],
    1,
    '',
  ],
  [
    '飲む',
    'のむ',
    'v5m',
    'vt',
    0,
    ['to drink'],
    2,
    '',
  ],
  [
    '走る',
    'はしる',
    'v5r',
    'vi',
    0,
    ['to run'],
    3,
    '',
  ],
];

/// A 16x16 AVIF, left half blue and right half red, made with Pillow.
const _avifBase64 =
    'AAAAIGZ0eXBhdmlmAAAAAGF2aWZtaWYxbWlhZk1BMUIAAADrbWV0YQAAAAAAAAAhaGRscgAAAAAA'
    'AAAAcGljdAAAAAAAAAAAAAAAAAAAAAAOcGl0bQAAAAAAAQAAAB5pbG9jAAAAAEQAAAEAAQAAAAEA'
    'AAETAAAAHwAAAChpaW5mAAAAAAABAAAAGmluZmUCAAAAAAEAAGF2MDFDb2xvcgAAAABqaXBycAAA'
    'AEtpcGNvAAAAFGlzcGUAAAAAAAAAEAAAABAAAAAQcGl4aQAAAAADCAgIAAAADGF2MUOBAAwAAAAA'
    'E2NvbHJuY2x4AAEADQAGgAAAABdpcG1hAAAAAAAAAAEAAQQBAoMEAAAAJ21kYXQSAAoGGAz/2BCA'
    'MhNFkAGGGGFAf7loqvNgQFtBgr7e';

Future<String> _writeFixtureZip(
  Directory dir, {
  required String title,
  Map<String, List<int>> extraFiles = const {},
}) async {
  final archive = Archive();

  final indexBytes = utf8.encode(
    jsonEncode({'title': title, 'format': 3, 'revision': '1.0'}),
  );
  archive.addFile(ArchiveFile('index.json', indexBytes.length, indexBytes));

  final termBankBytes = utf8.encode(jsonEncode(_entries));
  archive.addFile(
    ArchiveFile('term_bank_1.json', termBankBytes.length, termBankBytes),
  );

  for (final MapEntry(key: name, value: bytes) in extraFiles.entries) {
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  final zipPath = '${dir.path}/test_dict.zip';
  final bytes = ZipEncoder().encode(archive);
  await File(zipPath).writeAsBytes(bytes);
  return zipPath;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('yomitan_import_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'importing a Yomitan ZIP creates the dictionary, populates entries, and makes them queryable',
    () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repo = DictionaryRepository(db);
      final importer = DictionaryImporter(repo);
      final query = DictionaryQueryService(db);

      final zipPath = await _writeFixtureZip(tempDir, title: 'Test Dict');
      final inserted = await importer.importFromFile(zipPath);
      expect(inserted, _entries.length);

      // Dictionary metadata row exists with the title from index.json.
      final dicts = await repo.getAllDictionaries();
      expect(dicts, hasLength(1));
      expect(dicts.first.name, 'Test Dict');
      expect(dicts.first.isEnabled, isTrue);
      expect(await repo.getEntryCount(dicts.first.id), _entries.length);

      // The newly imported entries are reachable through the query service.
      // This catches regressions where the import succeeds but joins against
      // DictionaryMetas (the isEnabled filter) silently exclude the new rows.
      final taberu = await query.searchByExpression('食べる');
      expect(taberu, hasLength(1));
      expect(taberu.single.reading, 'たべる');
      expect(taberu.single.dictionaryId, dicts.first.id);
      final decodedGlossary = jsonDecode(taberu.single.glossaries) as List;
      expect(decodedGlossary, ['to eat']);
    },
  );

  test(
    'DictionaryQueryService honors the isEnabled toggle after import',
    () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repo = DictionaryRepository(db);
      final importer = DictionaryImporter(repo);
      final query = DictionaryQueryService(db);

      final zipPath = await _writeFixtureZip(tempDir, title: 'Toggle Dict');
      await importer.importFromFile(zipPath);
      final dict = (await repo.getAllDictionaries()).single;

      expect(await query.hasMatch('飲む'), isTrue);

      await repo.toggleDictionary(dict.id, isEnabled: false);
      // Production code invalidates the metas cache on toggle; replicate that.
      query.invalidateMetasCache();

      expect(await query.hasMatch('飲む'), isFalse);

      await repo.toggleDictionary(dict.id, isEnabled: true);
      query.invalidateMetasCache();
      expect(await query.hasMatch('飲む'), isTrue);
    },
  );

  test('an imported AVIF image is stored so Flutter can draw it', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repo = DictionaryRepository(db);

    final zipPath = await _writeFixtureZip(
      tempDir,
      title: 'Graphics',
      extraFiles: {'graphics/pattern.avif': base64Decode(_avifBase64)},
    );
    await DictionaryImporter(repo).importFromFile(zipPath);

    final id = (await repo.getAllDictionaries()).single.id;
    final stored = (await repo.getMedia(id, 'graphics/pattern.avif'))!;
    // Flutter cannot decode AVIF on iOS, so the import converts it to PNG
    // there; on Android the platform decoder reads the AVIF itself.
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      expect(stored.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    }

    final codec = await ui.instantiateImageCodec(stored);
    final image = (await codec.getNextFrame()).image;
    expect((image.width, image.height), (16, 16));
    final pixels = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    int channel(int x, int y, int offset) =>
        pixels.getUint8((y * 16 + x) * 4 + offset);
    // Lossy, so compare channels rather than exact values.
    expect(channel(3, 8, 2), greaterThan(channel(3, 8, 0))); // blue left
    expect(channel(12, 8, 0), greaterThan(channel(12, 8, 2))); // red right
  });
}
