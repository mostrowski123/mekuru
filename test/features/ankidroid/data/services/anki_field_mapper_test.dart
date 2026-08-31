import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/ankidroid/data/models/ankidroid_config.dart';
import 'package:mekuru/features/ankidroid/data/models/anki_note_data.dart';
import 'package:mekuru/features/ankidroid/data/services/anki_field_mapper.dart';

void main() {
  group('staleMappedFields', () {
    test('reports mapped fields that no longer exist in Anki', () {
      final stale = AnkiFieldMapper.staleMappedFields(
        ankiFieldNames: ['Word', 'Meaning'],
        fieldMapping: {'Front': 'expression', 'Word': 'reading'},
      );

      expect(stale, ['Front']);
    });

    test('ignores missing fields that were mapped to empty', () {
      final stale = AnkiFieldMapper.staleMappedFields(
        ankiFieldNames: ['Word'],
        fieldMapping: {'Front': 'empty', 'Word': 'expression'},
      );

      expect(stale, isEmpty);
    });

    test('returns nothing when the mapping matches Anki', () {
      final stale = AnkiFieldMapper.staleMappedFields(
        ankiFieldNames: ['Front', 'Back'],
        fieldMapping: {'Front': 'expression', 'Back': 'glossary'},
      );

      expect(stale, isEmpty);
    });
  });

  group('resolveAnkiFirstFieldValue', () {
    const noteData = AnkiNoteData(
      expression: '食べる',
      reading: 'タベル',
      glossaries: '[]',
      dictionaryName: 'Test Dictionary',
      sentenceContext: 'ご飯を食べる。',
    );

    test('uses the configured first field order', () {
      const config = AnkidroidConfig(
        modelId: 1,
        deckId: 2,
        fieldMapping: {'Reading': 'reading', 'Expression': 'expression'},
      );

      final firstFieldValue = resolveAnkiFirstFieldValue(
        config: config,
        noteData: noteData,
      );

      expect(firstFieldValue, 'タベル');
    });

    test('returns null when the first field resolves to blank content', () {
      const config = AnkidroidConfig(
        modelId: 1,
        deckId: 2,
        fieldMapping: {'Reading': 'empty', 'Expression': 'expression'},
      );

      final firstFieldValue = resolveAnkiFirstFieldValue(
        config: config,
        noteData: noteData,
      );

      expect(firstFieldValue, isNull);
    });
  });
}
