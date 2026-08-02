import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/vocabulary/data/repositories/vocabulary_repository.dart';

import 'shared/test_infrastructure.dart';

Future<int> _insertWord(
  AppDatabase db, {
  required String expression,
  String reading = '',
  required List<String> glossaries,
  String sentenceContext = '',
}) => db
    .into(db.savedWords)
    .insert(
      SavedWordsCompanion.insert(
        expression: expression,
        reading: Value(reading),
        glossaries: jsonEncode(glossaries),
        sentenceContext: Value(sentenceContext),
      ),
    );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('VocabularyRepository.exportToCsv', () {
    late AppDatabase db;
    late VocabularyRepository repo;

    setUp(() {
      db = createTestDatabase();
      repo = VocabularyRepository(db);
    });
    tearDown(() => db.close());

    test(
      'CSV export preserves Anki-compatible header and escapes embedded commas, quotes, newlines',
      () async {
        await _insertWord(
          db,
          expression: '食べる',
          reading: 'たべる',
          glossaries: ['to eat', 'to consume', 'to take (a meal)'],
          sentenceContext: '毎日ご飯を食べる。',
        );
        // Embedded comma in context.
        await _insertWord(
          db,
          expression: '走る',
          reading: 'はしる',
          glossaries: ['to run'],
          sentenceContext: 'いち、に、三、と数えて走る。',
        );
        // Embedded double quotes in context.
        await _insertWord(
          db,
          expression: '言う',
          reading: 'いう',
          glossaries: ['to say'],
          sentenceContext: '彼は"こんにちは"と言った。',
        );
        // Embedded newline in context.
        await _insertWord(
          db,
          expression: '読む',
          reading: 'よむ',
          glossaries: ['to read'],
          sentenceContext: 'First line\nSecond line',
        );
        // Expression-only entry (no reading, no context).
        await _insertWord(
          db,
          expression: 'ABC',
          reading: '',
          glossaries: ['just letters'],
          sentenceContext: '',
        );

        final exportedFile = await repo.exportToCsv();
        addTearDown(() async {
          if (await exportedFile.exists()) await exportedFile.delete();
        });

        final rows = const CsvDecoder().convert(
          await exportedFile.readAsString(),
        );

        // The header matches what users paste into the Anki import dialog;
        // renaming a column here would silently break their saved templates.
        expect(rows.first, [
          'Word',
          'Reading',
          'Meaning',
          'Furigana',
          'Context',
        ]);

        final byExpression = {
          for (final row in rows.skip(1)) row[0] as String: row,
        };
        expect(byExpression.keys, {'食べる', '走る', '言う', '読む', 'ABC'});

        final taberu = byExpression['食べる']!;
        expect(taberu[1], 'たべる');
        expect(taberu[2], 'to eat; to consume; to take (a meal)');
        // Furigana wiring smoke check; full coverage is in anki_field_mapper_test.
        expect(taberu[3], isNot(isEmpty));
        expect(taberu[4], '毎日ご飯を食べる。');

        expect(byExpression['走る']![4], 'いち、に、三、と数えて走る。');
        expect(byExpression['言う']![4], '彼は"こんにちは"と言った。');
        expect(byExpression['読む']![4], 'First line\nSecond line');

        final abc = byExpression['ABC']!;
        // No-reading, no-context row stays empty rather than printing nulls.
        expect(abc[1], '');
        expect(abc[2], 'just letters');
        expect(abc[4], '');
      },
    );

    test('CSV export with selectedIds only includes those words', () async {
      final keepId = await _insertWord(
        db,
        expression: '残す',
        reading: 'のこす',
        glossaries: ['to keep'],
      );
      await _insertWord(
        db,
        expression: '捨てる',
        reading: 'すてる',
        glossaries: ['to discard'],
      );

      final exportedFile = await repo.exportToCsv(selectedIds: {keepId});
      addTearDown(() async {
        if (await exportedFile.exists()) await exportedFile.delete();
      });

      final rows = const CsvDecoder().convert(
        await exportedFile.readAsString(),
      );

      expect(rows, hasLength(2));
      expect(rows[1][0], '残す');
    });
  });
}
