import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/backup/data/services/backup_serializer.dart';
import 'package:mekuru/features/backup/data/services/backup_service.dart';
import 'package:mekuru/features/backup/data/services/book_match_service.dart';
import 'package:mekuru/features/dictionary/data/models/dictionary_meta.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_query_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dictionary_fts_test_support.dart';
import 'shared/test_database.dart';

void main() {
  late AppDatabase db;
  late DictionaryRepository repo;
  late DictionaryQueryService queryService;

  // The backup round trip restores into a second database.
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  setUp(() {
    db = createTestDatabase();
    repo = DictionaryRepository(db);
    queryService = DictionaryQueryService(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<List<DictionaryEntry>> userEntries() => repo.getUserDefinitions();

  group('user definitions', () {
    test('adding the first one creates the user dictionary after the others '
        'and is found by lookup and English search', () async {
      await repo.insertDictionary('JMdict');
      await repo.addUserDefinition(
        term: ' ぴえん ',
        reading: '',
        definition: 'Crying emoji feeling\nused online',
      );

      final meta = (await repo.getAllDictionaries()).last;
      expect(meta.id, userDictionaryId);
      expect(meta.name, DictionaryRepository.userDictionaryName);
      expect(meta.isEnabled, isTrue);

      final [entry] = await userEntries();
      expect(entry.expression, 'ぴえん');
      expect(entry.glossaries, '["Crying emoji feeling\\nused online"]');
      expect(entry.searchText, 'crying emoji feeling\nused online');

      final found = await queryService.searchLookupWithSource('ぴえん');
      expect(found.map((r) => r.entry.id), [entry.id]);
      expect(found.single.dictionaryName, 'My definitions');

      final english = await queryService.glossarySearchWithSource('emoji');
      expect(english.map((r) => r.entry.id), [entry.id]);
      await expectGlossaryFtsConsistent(db);
    });

    test('a second one reuses the user dictionary', () async {
      await repo.addUserDefinition(term: 'ぴえん', definition: 'sad');
      await repo.addUserDefinition(term: 'ぱおん', definition: 'very sad');

      expect(await repo.getAllDictionaries(), hasLength(1));
      expect(await userEntries(), hasLength(2));
    });

    test('editing refreshes searchText and the FTS index', () async {
      await repo.addUserDefinition(term: 'ぴえん', definition: 'sad');
      final [entry] = await userEntries();

      await repo.updateUserDefinition(
        entry.id,
        term: 'ぴえん',
        reading: 'ぴえん',
        definition: 'Teary pleading face',
      );

      final [edited] = await userEntries();
      expect(edited.reading, 'ぴえん');
      expect(edited.searchText, 'teary pleading face');
      expect(
        DictionaryRepository.userDefinitionText(edited),
        'Teary pleading face',
      );
      expect(await queryService.glossarySearchWithSource('sad'), isEmpty);
      expect(
        await queryService.glossarySearchWithSource('teary'),
        hasLength(1),
      );
      await expectGlossaryFtsConsistent(db);
    });

    test('deleting removes it from lookups', () async {
      await repo.addUserDefinition(term: 'ぴえん', definition: 'sad');
      final [entry] = await userEntries();

      await repo.deleteUserDefinition(entry.id);

      expect(await userEntries(), isEmpty);
      expect(await queryService.searchLookupWithSource('ぴえん'), isEmpty);
      await expectGlossaryFtsConsistent(db);
    });

    test('edit and delete leave other dictionaries alone', () async {
      final jmdict = await repo.insertDictionary('JMdict');
      await repo.batchInsertEntries([
        DictionaryEntriesCompanion.insert(
          expression: '猫',
          glossaries: '["cat"]',
          dictionaryId: jmdict,
        ),
      ]);
      final cat = (await db.select(db.dictionaryEntries).get()).single;

      await repo.updateUserDefinition(cat.id, term: 'x', definition: 'y');
      await repo.deleteUserDefinition(cat.id);

      expect((await db.select(db.dictionaryEntries).get()).single, cat);
    });

    test('a disabled user dictionary returns nothing', () async {
      await repo.addUserDefinition(term: 'ぴえん', definition: 'sad');
      await repo.toggleDictionary(userDictionaryId, isEnabled: false);
      queryService.invalidateMetasCache();

      expect(await queryService.searchLookupWithSource('ぴえん'), isEmpty);
      expect(await queryService.glossarySearchWithSource('sad'), isEmpty);
    });

    test('adding a definition turns the user dictionary back on', () async {
      await repo.addUserDefinition(term: 'ぴえん', definition: 'sad');
      await repo.toggleDictionary(userDictionaryId, isEnabled: false);
      await repo.addUserDefinition(term: 'ぱおん', definition: 'very sad');
      queryService.invalidateMetasCache();

      expect(await queryService.searchLookupWithSource('ぴえん'), isNotEmpty);
    });
  });

  group('backup', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test(
      'round-trips user definitions and merges without duplicates',
      () async {
        await repo.addUserDefinition(
          term: 'ぴえん',
          reading: 'ぴえん',
          definition: 'sad\nonline',
        );
        await repo.addUserDefinition(term: 'ぱおん', definition: 'very sad');

        final json = BackupSerializer.encode(
          await BackupService(db, BookMatchService()).createBackup(),
        );
        final manifest = BackupSerializer.decode(json);
        expect(manifest.userDefinitions.map((d) => d.definition), [
          'sad\nonline',
          'very sad',
        ]);

        final target = createTestDatabase();
        addTearDown(target.close);
        final targetRepo = DictionaryRepository(target);
        await targetRepo.addUserDefinition(term: 'ぱおん', definition: 'very sad');
        final definitions = [
          for (final d in manifest.userDefinitions)
            (term: d.term, reading: d.reading, definition: d.definition),
        ];

        expect(await targetRepo.mergeUserDefinitions(definitions), 1);
        expect(await targetRepo.mergeUserDefinitions(definitions), 0);

        final restored = await targetRepo.getUserDefinitions();
        expect(
          restored.map(
            (e) => (
              e.expression,
              e.reading,
              DictionaryRepository.userDefinitionText(e),
            ),
          ),
          unorderedEquals([
            ('ぱおん', '', 'very sad'),
            ('ぴえん', 'ぴえん', 'sad\nonline'),
          ]),
        );
      },
    );

    test('restoring creates the user dictionary when missing', () async {
      expect(
        await repo.mergeUserDefinitions([
          (term: 'ぴえん', reading: '', definition: 'sad'),
          (term: ' ', reading: '', definition: 'blank word'),
          (term: 'ぱおん', reading: '', definition: ''),
        ]),
        1,
      );
      expect((await repo.getAllDictionaries()).single.id, userDictionaryId);
    });

    test('an old backup without user definitions still restores', () async {
      final manifest = BackupSerializer.decode(
        '{"version":1,"createdAt":"2026-01-01T00:00:00.000Z",'
        '"settings":{"app":{},"reader":{}},"savedWords":[],"books":[]}',
      );

      expect(manifest.userDefinitions, isEmpty);
      expect(await repo.mergeUserDefinitions(const []), 0);
      expect(await repo.getAllDictionaries(), isEmpty);
    });
  });
}
