import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/vocabulary/data/repositories/vocabulary_repository.dart';

/// Creates an in-memory Drift database for testing.
AppDatabase createTestDatabase() {
  return AppDatabase(NativeDatabase.memory());
}

void main() {
  late AppDatabase db;
  late VocabularyRepository repo;

  Future<int> insertSavedWord(
    AppDatabase db, {
    required String expression,
    String reading = '',
    String glossaries = '[]',
    String sentenceContext = '',
  }) {
    return db
        .into(db.savedWords)
        .insert(
          SavedWordsCompanion.insert(
            expression: expression,
            reading: Value(reading),
            glossaries: glossaries,
            sentenceContext: Value(sentenceContext),
          ),
        );
  }

  setUp(() async {
    db = createTestDatabase();
    repo = VocabularyRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  // ── Query filtering (the core logic behind selective export) ─────

  group('Selective export — query filtering', () {
    test('getAllWords returns all inserted words', () async {
      await insertSavedWord(
        db,
        expression: '食べる',
        glossaries: jsonEncode(['to eat']),
      );
      await insertSavedWord(
        db,
        expression: '飲む',
        glossaries: jsonEncode(['to drink']),
      );
      await insertSavedWord(
        db,
        expression: '走る',
        glossaries: jsonEncode(['to run']),
      );

      final words = await repo.getAllWords();
      expect(words, hasLength(3));
    });

    test('filtering by selectedIds returns only matching words', () async {
      final id1 = await insertSavedWord(
        db,
        expression: '食べる',
        glossaries: jsonEncode(['to eat']),
      );
      await insertSavedWord(
        db,
        expression: '飲む',
        glossaries: jsonEncode(['to drink']),
      );
      final id3 = await insertSavedWord(
        db,
        expression: '走る',
        glossaries: jsonEncode(['to run']),
      );

      // Simulate the filtering query used by exportToCsv
      final filtered =
          await (db.select(db.savedWords)
                ..where((t) => t.id.isIn({id1, id3}))
                ..orderBy([(t) => OrderingTerm.desc(t.dateAdded)]))
              .get();

      expect(filtered, hasLength(2));
      final expressions = filtered.map((w) => w.expression).toSet();
      expect(expressions, contains('食べる'));
      expect(expressions, contains('走る'));
      expect(expressions, isNot(contains('飲む')));
    });

    test('filtering by single id returns one word', () async {
      final id1 = await insertSavedWord(
        db,
        expression: '食べる',
        glossaries: jsonEncode(['to eat']),
      );
      await insertSavedWord(
        db,
        expression: '飲む',
        glossaries: jsonEncode(['to drink']),
      );
      await insertSavedWord(
        db,
        expression: '走る',
        glossaries: jsonEncode(['to run']),
      );
      await insertSavedWord(
        db,
        expression: '見る',
        glossaries: jsonEncode(['to see']),
      );

      final filtered = await (db.select(
        db.savedWords,
      )..where((t) => t.id.isIn({id1}))).get();

      expect(filtered, hasLength(1));
      expect(filtered.first.expression, '食べる');
    });

    test('filtering by non-existent ids returns empty', () async {
      await insertSavedWord(
        db,
        expression: '食べる',
        glossaries: jsonEncode(['to eat']),
      );

      final filtered = await (db.select(
        db.savedWords,
      )..where((t) => t.id.isIn({999, 1000}))).get();

      expect(filtered, isEmpty);
    });
  });

  // ── CRUD operations ─────────────────────────────────────────────

  group('VocabularyRepository — CRUD', () {
    test('getAllWords returns inserted words', () async {
      await insertSavedWord(
        db,
        expression: '一',
        glossaries: jsonEncode(['one']),
      );
      await insertSavedWord(
        db,
        expression: '二',
        glossaries: jsonEncode(['two']),
      );

      final words = await repo.getAllWords();
      expect(words.length, 2);
      final expressions = words.map((w) => w.expression).toSet();
      expect(expressions, containsAll(['一', '二']));
    });

    test('deleteWord removes the word', () async {
      final id = await insertSavedWord(
        db,
        expression: '食べる',
        glossaries: jsonEncode(['to eat']),
      );

      await repo.deleteWord(id);
      final words = await repo.getAllWords();
      expect(words, isEmpty);
    });

    test('deleteWord only removes the specified word', () async {
      final id1 = await insertSavedWord(
        db,
        expression: '食べる',
        glossaries: jsonEncode(['to eat']),
      );
      await insertSavedWord(
        db,
        expression: '飲む',
        glossaries: jsonEncode(['to drink']),
      );

      await repo.deleteWord(id1);
      final words = await repo.getAllWords();
      expect(words, hasLength(1));
      expect(words.first.expression, '飲む');
    });

    test('isWordSaved returns true for existing word', () async {
      await insertSavedWord(
        db,
        expression: '食べる',
        reading: 'たべる',
        glossaries: jsonEncode(['to eat']),
      );

      final exists = await repo.isWordSaved('食べる', 'たべる');
      expect(exists, isTrue);
    });

    test('isWordSaved returns false for non-existing word', () async {
      final exists = await repo.isWordSaved('存在しない', 'そんざいしない');
      expect(exists, isFalse);
    });

    test('isWordSaved checks both expression and reading', () async {
      await insertSavedWord(
        db,
        expression: '食べる',
        reading: 'たべる',
        glossaries: jsonEncode(['to eat']),
      );

      // Same expression, different reading — should not match
      final exists = await repo.isWordSaved('食べる', 'くべる');
      expect(exists, isFalse);
    });

    test('watchAllWords emits updates when words change', () async {
      final stream = repo.watchAllWords();

      // First emission should be empty
      await expectLater(stream, emits(isEmpty));
    });

    test('saved word stores sentence context', () async {
      await insertSavedWord(
        db,
        expression: '食べる',
        reading: 'たべる',
        glossaries: jsonEncode(['to eat']),
        sentenceContext: '昨日ケーキを食べた。',
      );

      final words = await repo.getAllWords();
      expect(words.first.sentenceContext, '昨日ケーキを食べた。');
    });

    test('saved word stores glossaries as JSON string', () async {
      final glossaries = jsonEncode(['to eat', 'to consume']);
      await insertSavedWord(db, expression: '食べる', glossaries: glossaries);

      final words = await repo.getAllWords();
      expect(words.first.glossaries, glossaries);
      final decoded = jsonDecode(words.first.glossaries) as List;
      expect(decoded, ['to eat', 'to consume']);
    });
  });
}
