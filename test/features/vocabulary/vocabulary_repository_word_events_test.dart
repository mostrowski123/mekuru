import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/models/dictionary_entry.dart';
import 'package:mekuru/features/vocabulary/data/repositories/vocabulary_repository.dart';

AppDatabase createTestDatabase() => AppDatabase(NativeDatabase.memory());

DictionaryEntry buildEntry({String expression = '猫'}) => DictionaryEntry(
  id: 1,
  expression: expression,
  reading: 'ねこ',
  entryKind: DictionaryEntryKinds.regular,
  kanjiOnyomi: '',
  kanjiKunyomi: '',
  definitionTags: 'n',
  rules: '',
  termTags: '',
  glossaries: '["cat"]',
  searchText: '',
  dictionaryId: 1,
);

void main() {
  late AppDatabase db;
  late VocabularyRepository repository;

  setUp(() {
    db = createTestDatabase();
    repository = VocabularyRepository(db);
  });
  tearDown(() async => db.close());

  test(
    'addWord records a saved word event defaulting to source other',
    () async {
      await repository.addWord(entry: buildEntry());

      final events = await db.select(db.wordEvents).get();

      expect(events.single.kind, 'saved');
      expect(events.single.expression, '猫');
      expect(events.single.source, 'other');
    },
  );

  test('addWord records the supplied source on the word event', () async {
    await repository.addWord(
      entry: buildEntry(expression: '犬'),
      source: 'manga',
    );

    final events = await db.select(db.wordEvents).get();

    expect(events.single.kind, 'saved');
    expect(events.single.expression, '犬');
    expect(events.single.source, 'manga');
  });

  test('addWord still saves the word when the stats write fails', () async {
    // Simulates installs whose stats tables never made it through migration.
    await db.customStatement('DROP TABLE word_events');

    final id = await repository.addWord(entry: buildEntry(expression: '鳥'));

    final saved = await (db.select(
      db.savedWords,
    )..where((t) => t.id.equals(id))).getSingle();
    expect(saved.expression, '鳥');
  });

  test('restoreWord does not record a word event', () async {
    final id = await repository.addWord(entry: buildEntry());
    final saved = await (db.select(
      db.savedWords,
    )..where((t) => t.id.equals(id))).getSingle();
    await repository.deleteWord(id);

    await repository.restoreWord(saved);

    final events = await db.select(db.wordEvents).get();
    expect(events, hasLength(1));
  });
}
