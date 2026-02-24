import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';

/// Creates an in-memory Drift database for testing.
AppDatabase createTestDatabase() {
  return AppDatabase(NativeDatabase.memory());
}

void main() {
  late AppDatabase db;
  late DictionaryRepository repo;

  setUp(() {
    db = createTestDatabase();
    repo = DictionaryRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('DictionaryRepository — DictionaryMeta', () {
    test(
      'insertDictionary creates a new dictionary and returns its id',
      () async {
        final id = await repo.insertDictionary('JMdict');
        expect(id, greaterThan(0));
      },
    );

    test('getAllDictionaries returns all inserted dictionaries', () async {
      await repo.insertDictionary('JMdict');
      await repo.insertDictionary('JMnedict');

      final dicts = await repo.getAllDictionaries();
      expect(dicts, hasLength(2));
      expect(dicts.map((d) => d.name), containsAll(['JMdict', 'JMnedict']));
    });

    test('new dictionaries are enabled by default', () async {
      await repo.insertDictionary('JMdict');

      final dicts = await repo.getAllDictionaries();
      expect(dicts.first.isEnabled, isTrue);
    });

    test('toggleDictionary disables and re-enables a dictionary', () async {
      final id = await repo.insertDictionary('JMdict');

      // Disable
      await repo.toggleDictionary(id, isEnabled: false);
      var dicts = await repo.getAllDictionaries();
      expect(dicts.first.isEnabled, isFalse);

      // Re-enable
      await repo.toggleDictionary(id, isEnabled: true);
      dicts = await repo.getAllDictionaries();
      expect(dicts.first.isEnabled, isTrue);
    });

    test('deleteDictionary removes the dictionary and all entries', () async {
      final id = await repo.insertDictionary('JMdict');

      // Insert entries for this dictionary
      await repo.batchInsertEntries([
        DictionaryEntriesCompanion.insert(
          expression: '食べる',
          glossaries: '["to eat"]',
          dictionaryId: id,
        ),
        DictionaryEntriesCompanion.insert(
          expression: '飲む',
          glossaries: '["to drink"]',
          dictionaryId: id,
        ),
      ]);

      expect(await repo.getEntryCount(id), 2);

      // Delete the dictionary
      await repo.deleteDictionary(id);

      final dicts = await repo.getAllDictionaries();
      expect(dicts, isEmpty);
      expect(await repo.getEntryCount(id), 0);
    });
  });

  group('DictionaryRepository — DictionaryEntry', () {
    test('batchInsertEntries inserts entries correctly', () async {
      final dictId = await repo.insertDictionary('JMdict');

      final entries = List.generate(
        50,
        (i) => DictionaryEntriesCompanion.insert(
          expression: 'word_$i',
          reading: Value('reading_$i'),
          glossaries: jsonEncode(['meaning_$i']),
          dictionaryId: dictId,
        ),
      );

      final count = await repo.batchInsertEntries(entries);
      expect(count, 50);
      expect(await repo.getEntryCount(dictId), 50);
    });

    test('batchInsertEntries respects batchSize chunking', () async {
      final dictId = await repo.insertDictionary('JMdict');

      // Create 25 entries but insert in batches of 10
      final entries = List.generate(
        25,
        (i) => DictionaryEntriesCompanion.insert(
          expression: 'word_$i',
          glossaries: jsonEncode(['meaning_$i']),
          dictionaryId: dictId,
        ),
      );

      final count = await repo.batchInsertEntries(entries, batchSize: 10);
      expect(count, 25);
      expect(await repo.getEntryCount(dictId), 25);
    });

    test('getEntryCount returns 0 for non-existent dictionary', () async {
      expect(await repo.getEntryCount(999), 0);
    });

    test('getTotalEntryCount counts entries across all dictionaries', () async {
      final id1 = await repo.insertDictionary('Dict1');
      final id2 = await repo.insertDictionary('Dict2');

      await repo.batchInsertEntries([
        DictionaryEntriesCompanion.insert(
          expression: '食べる',
          glossaries: '["to eat"]',
          dictionaryId: id1,
        ),
      ]);
      await repo.batchInsertEntries([
        DictionaryEntriesCompanion.insert(
          expression: '飲む',
          glossaries: '["to drink"]',
          dictionaryId: id2,
        ),
        DictionaryEntriesCompanion.insert(
          expression: '走る',
          glossaries: '["to run"]',
          dictionaryId: id2,
        ),
      ]);

      expect(await repo.getTotalEntryCount(), 3);
    });

    test('deleting one dictionary does not affect another', () async {
      final id1 = await repo.insertDictionary('Dict1');
      final id2 = await repo.insertDictionary('Dict2');

      await repo.batchInsertEntries([
        DictionaryEntriesCompanion.insert(
          expression: '食べる',
          glossaries: '["to eat"]',
          dictionaryId: id1,
        ),
      ]);
      await repo.batchInsertEntries([
        DictionaryEntriesCompanion.insert(
          expression: '飲む',
          glossaries: '["to drink"]',
          dictionaryId: id2,
        ),
      ]);

      await repo.deleteDictionary(id1);

      expect(await repo.getEntryCount(id2), 1);
      expect(await repo.getTotalEntryCount(), 1);
    });
  });

  group('DictionaryRepository — sort order', () {
    test('insertDictionary assigns sequential sort order', () async {
      await repo.insertDictionary('Dict A');
      await repo.insertDictionary('Dict B');
      await repo.insertDictionary('Dict C');

      final dicts = await repo.getAllDictionaries();
      expect(dicts.map((d) => d.name).toList(), ['Dict A', 'Dict B', 'Dict C']);
      expect(dicts[0].sortOrder, 0);
      expect(dicts[1].sortOrder, 1);
      expect(dicts[2].sortOrder, 2);
    });

    test('getAllDictionaries returns in sort order', () async {
      // Insert in order, then reorder
      await repo.insertDictionary('Dict A');
      await repo.insertDictionary('Dict B');
      await repo.insertDictionary('Dict C');

      final original = await repo.getAllDictionaries();
      // Reverse: C, B, A
      await repo.reorderDictionaries([
        original[2].id,
        original[1].id,
        original[0].id,
      ]);

      final reordered = await repo.getAllDictionaries();
      expect(
        reordered.map((d) => d.name).toList(),
        ['Dict C', 'Dict B', 'Dict A'],
      );
    });

    test('reorderDictionaries persists new order', () async {
      await repo.insertDictionary('Dict A');
      await repo.insertDictionary('Dict B');
      await repo.insertDictionary('Dict C');

      final original = await repo.getAllDictionaries();
      // Move C to front: C, A, B
      await repo.reorderDictionaries([
        original[2].id,
        original[0].id,
        original[1].id,
      ]);

      final reordered = await repo.getAllDictionaries();
      expect(
        reordered.map((d) => d.name).toList(),
        ['Dict C', 'Dict A', 'Dict B'],
      );
      expect(reordered[0].sortOrder, 0);
      expect(reordered[1].sortOrder, 1);
      expect(reordered[2].sortOrder, 2);
    });

    test('getNextSortOrder returns 0 when no dictionaries exist', () async {
      final next = await repo.getNextSortOrder();
      expect(next, 0);
    });

    test('getNextSortOrder returns max + 1', () async {
      await repo.insertDictionary('Dict A');
      await repo.insertDictionary('Dict B');
      final next = await repo.getNextSortOrder();
      expect(next, 2);
    });

    test('new dictionary gets appended after reorder', () async {
      await repo.insertDictionary('Dict A');
      await repo.insertDictionary('Dict B');

      final original = await repo.getAllDictionaries();
      // Reverse: B, A
      await repo.reorderDictionaries([original[1].id, original[0].id]);

      // Import a new one — should append at the end
      await repo.insertDictionary('Dict C');

      final all = await repo.getAllDictionaries();
      expect(all.map((d) => d.name).toList(), ['Dict B', 'Dict A', 'Dict C']);
    });
  });

  group('DictionaryRepository — watchAllDictionaries', () {
    test('stream emits updates when dictionaries change', () async {
      // Collect all emissions from the stream
      final emissions = <List<DictionaryMeta>>[];
      final subscription = repo.watchAllDictionaries().listen((data) {
        emissions.add(data);
      });

      // Wait briefly for initial emission
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(emissions.last, hasLength(0));

      // Insert a dictionary and wait for the stream to update
      await repo.insertDictionary('JMdict');
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(emissions.last, hasLength(1));
      expect(emissions.last.first.name, 'JMdict');

      await subscription.cancel();
    });
  });

  group('DictionaryRepository — setHidden', () {
    test('marks a dictionary as hidden', () async {
      final id = await repo.insertDictionary('FreqDict');

      await repo.setHidden(id, isHidden: true);
      final dicts = await repo.getAllDictionaries();
      expect(dicts.first.isHidden, isTrue);
    });

    test('un-hides a dictionary', () async {
      final id = await repo.insertDictionary('FreqDict');
      await repo.setHidden(id, isHidden: true);
      await repo.setHidden(id, isHidden: false);

      final dicts = await repo.getAllDictionaries();
      expect(dicts.first.isHidden, isFalse);
    });

    test('new dictionaries are not hidden by default', () async {
      await repo.insertDictionary('JMdict');
      final dicts = await repo.getAllDictionaries();
      expect(dicts.first.isHidden, isFalse);
    });
  });

  group('DictionaryRepository — getDictionaryByName', () {
    test('returns dictionary when name exists', () async {
      await repo.insertDictionary('JMdict');
      final result = await repo.getDictionaryByName('JMdict');
      expect(result, isNot(equals(null)));
      expect(result!.name, 'JMdict');
    });

    test('returns null when name does not exist', () async {
      final result = await repo.getDictionaryByName('NonExistent');
      expect(result, equals(null));
    });

    test('matches exact name only', () async {
      await repo.insertDictionary('JMdict');
      final exactResult = await repo.getDictionaryByName('JMdict');
      expect(exactResult, isNot(equals(null)));
    });
  });

  group('DictionaryRepository — watchVisibleDictionaries', () {
    test('excludes hidden dictionaries', () async {
      final id1 = await repo.insertDictionary('Visible');
      final id2 = await repo.insertDictionary('Hidden');
      await repo.setHidden(id2, isHidden: true);

      final emissions = <List<DictionaryMeta>>[];
      final subscription = repo.watchVisibleDictionaries().listen((data) {
        emissions.add(data);
      });

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(emissions.last, hasLength(1));
      expect(emissions.last.first.name, 'Visible');

      await subscription.cancel();
    });
  });

  group('DictionaryRepository — PitchAccent operations', () {
    test('batchInsertPitchAccents inserts correctly', () async {
      final dictId = await repo.insertDictionary('PitchDict');

      final entries = [
        PitchAccentsCompanion.insert(
          expression: '食べる',
          reading: const Value('たべる'),
          downstepPosition: 2,
          dictionaryId: dictId,
        ),
        PitchAccentsCompanion.insert(
          expression: '走る',
          reading: const Value('はしる'),
          downstepPosition: 2,
          dictionaryId: dictId,
        ),
      ];

      final count = await repo.batchInsertPitchAccents(entries);
      expect(count, 2);
      expect(await repo.getPitchAccentCount(dictId), 2);
    });

    test('batchInsertPitchAccents respects batchSize', () async {
      final dictId = await repo.insertDictionary('PitchDict');

      final entries = List.generate(
        15,
        (i) => PitchAccentsCompanion.insert(
          expression: 'word_$i',
          reading: Value('reading_$i'),
          downstepPosition: i % 4,
          dictionaryId: dictId,
        ),
      );

      final count = await repo.batchInsertPitchAccents(entries, batchSize: 5);
      expect(count, 15);
      expect(await repo.getPitchAccentCount(dictId), 15);
    });

    test('getPitchAccentCount returns 0 for non-existent dictionary', () async {
      expect(await repo.getPitchAccentCount(999), 0);
    });
  });

  group('DictionaryRepository — Frequency operations', () {
    test('batchInsertFrequencies inserts correctly', () async {
      final dictId = await repo.insertDictionary('FreqDict');

      final entries = [
        FrequenciesCompanion.insert(
          expression: '食べる',
          reading: const Value('たべる'),
          frequencyRank: 100,
          dictionaryId: dictId,
        ),
        FrequenciesCompanion.insert(
          expression: '走る',
          reading: const Value('はしる'),
          frequencyRank: 500,
          dictionaryId: dictId,
        ),
      ];

      final count = await repo.batchInsertFrequencies(entries);
      expect(count, 2);
      expect(await repo.getFrequencyCount(dictId), 2);
    });

    test('batchInsertFrequencies respects batchSize', () async {
      final dictId = await repo.insertDictionary('FreqDict');

      final entries = List.generate(
        15,
        (i) => FrequenciesCompanion.insert(
          expression: 'word_$i',
          reading: Value('reading_$i'),
          frequencyRank: i * 100,
          dictionaryId: dictId,
        ),
      );

      final count = await repo.batchInsertFrequencies(entries, batchSize: 5);
      expect(count, 15);
      expect(await repo.getFrequencyCount(dictId), 15);
    });

    test('getFrequencyCount returns 0 for non-existent dictionary', () async {
      expect(await repo.getFrequencyCount(999), 0);
    });
  });

  group('DictionaryRepository — deleteDictionary cascades', () {
    test('deleting a dictionary also removes its pitch accents', () async {
      final dictId = await repo.insertDictionary('PitchDict');

      await repo.batchInsertPitchAccents([
        PitchAccentsCompanion.insert(
          expression: '食べる',
          reading: const Value('たべる'),
          downstepPosition: 2,
          dictionaryId: dictId,
        ),
      ]);
      expect(await repo.getPitchAccentCount(dictId), 1);

      await repo.deleteDictionary(dictId);
      expect(await repo.getPitchAccentCount(dictId), 0);
    });

    test('deleting a dictionary also removes its frequencies', () async {
      final dictId = await repo.insertDictionary('FreqDict');

      await repo.batchInsertFrequencies([
        FrequenciesCompanion.insert(
          expression: '食べる',
          reading: const Value('たべる'),
          frequencyRank: 100,
          dictionaryId: dictId,
        ),
      ]);
      expect(await repo.getFrequencyCount(dictId), 1);

      await repo.deleteDictionary(dictId);
      expect(await repo.getFrequencyCount(dictId), 0);
    });

    test('deleting one dictionary does not affect another pitch/freq data',
        () async {
      final id1 = await repo.insertDictionary('Dict1');
      final id2 = await repo.insertDictionary('Dict2');

      await repo.batchInsertPitchAccents([
        PitchAccentsCompanion.insert(
          expression: '食べる',
          reading: const Value('たべる'),
          downstepPosition: 2,
          dictionaryId: id1,
        ),
        PitchAccentsCompanion.insert(
          expression: '走る',
          reading: const Value('はしる'),
          downstepPosition: 1,
          dictionaryId: id2,
        ),
      ]);

      await repo.batchInsertFrequencies([
        FrequenciesCompanion.insert(
          expression: '食べる',
          reading: const Value('たべる'),
          frequencyRank: 100,
          dictionaryId: id1,
        ),
        FrequenciesCompanion.insert(
          expression: '走る',
          reading: const Value('はしる'),
          frequencyRank: 500,
          dictionaryId: id2,
        ),
      ]);

      await repo.deleteDictionary(id1);

      expect(await repo.getPitchAccentCount(id2), 1);
      expect(await repo.getFrequencyCount(id2), 1);
      expect(await repo.getEntryCount(id2), 0); // no entries were inserted for id2
    });

    test('deleting a dictionary removes entries, pitch accents, and frequencies together',
        () async {
      final dictId = await repo.insertDictionary('FullDict');

      await repo.batchInsertEntries([
        DictionaryEntriesCompanion.insert(
          expression: '食べる',
          glossaries: '["to eat"]',
          dictionaryId: dictId,
        ),
      ]);
      await repo.batchInsertPitchAccents([
        PitchAccentsCompanion.insert(
          expression: '食べる',
          reading: const Value('たべる'),
          downstepPosition: 2,
          dictionaryId: dictId,
        ),
      ]);
      await repo.batchInsertFrequencies([
        FrequenciesCompanion.insert(
          expression: '食べる',
          reading: const Value('たべる'),
          frequencyRank: 100,
          dictionaryId: dictId,
        ),
      ]);

      expect(await repo.getEntryCount(dictId), 1);
      expect(await repo.getPitchAccentCount(dictId), 1);
      expect(await repo.getFrequencyCount(dictId), 1);

      await repo.deleteDictionary(dictId);

      expect(await repo.getEntryCount(dictId), 0);
      expect(await repo.getPitchAccentCount(dictId), 0);
      expect(await repo.getFrequencyCount(dictId), 0);
      final dicts = await repo.getAllDictionaries();
      expect(dicts, isEmpty);
    });
  });
}
