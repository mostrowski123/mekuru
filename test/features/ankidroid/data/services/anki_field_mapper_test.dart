import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/ankidroid/data/models/ankidroid_config.dart';
import 'package:mekuru/features/ankidroid/data/models/anki_note_data.dart';
import 'package:mekuru/features/ankidroid/data/services/anki_field_mapper.dart';

void main() {
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
