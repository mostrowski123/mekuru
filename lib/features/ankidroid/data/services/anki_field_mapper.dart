import 'package:mekuru/features/ankidroid/data/models/anki_note_data.dart';
import 'package:mekuru/features/dictionary/data/services/glossary_parser.dart';
import 'package:mekuru/features/dictionary/data/services/romaji_converter.dart';

/// Available app data sources that can be mapped to Anki fields.
enum AppDataSource {
  expression('Expression', 'expression'),
  reading('Reading', 'reading'),
  furigana('Furigana (Anki format)', 'furigana'),
  glossary('Glossary / Meaning', 'glossary'),
  sentenceContext('Sentence Context', 'sentence_context'),
  frequency('Frequency Rank', 'frequency'),
  dictionaryName('Dictionary Name', 'dictionary_name'),
  pitchAccent('Pitch Accent', 'pitch_accent'),
  empty('(Empty)', 'empty');

  final String displayName;
  final String key;
  const AppDataSource(this.displayName, this.key);

  static AppDataSource fromKey(String key) {
    return AppDataSource.values.firstWhere(
      (e) => e.key == key,
      orElse: () => AppDataSource.empty,
    );
  }
}

/// Resolves field mappings against actual word data to produce Anki field values.
class AnkiFieldMapper {
  /// Given a mapping and note data, produce an ordered list of field values
  /// matching the Anki model's field order.
  static List<String> resolveFields({
    required List<String> ankiFieldNames,
    required Map<String, String> fieldMapping,
    required AnkiNoteData noteData,
  }) {
    return ankiFieldNames.map((fieldName) {
      final sourceKey = fieldMapping[fieldName] ?? 'empty';
      return _resolveValue(sourceKey, noteData);
    }).toList();
  }

  static String _resolveValue(String sourceKey, AnkiNoteData noteData) {
    return switch (sourceKey) {
      'expression' => noteData.expression,
      'reading' => noteData.reading,
      'furigana' => _formatFurigana(noteData),
      'glossary' => GlossaryParser.parse(noteData.glossaries).join('\n'),
      'sentence_context' => noteData.sentenceContext ?? '',
      'frequency' => noteData.frequencyRank?.toString() ?? '',
      'dictionary_name' => noteData.dictionaryName,
      'pitch_accent' => _formatPitchAccents(noteData),
      _ => '',
    };
  }

  static String _formatPitchAccents(AnkiNoteData noteData) {
    if (noteData.pitchAccents.isEmpty) return '';
    return noteData.pitchAccents
        .map((p) => '${p.reading} [${p.downstepPosition}]')
        .join(', ');
  }

  /// Whether a Unicode code unit is a CJK kanji character.
  static bool _isKanji(int codeUnit) {
    return (codeUnit >= 0x4E00 && codeUnit <= 0x9FFF) ||
        (codeUnit >= 0x3400 && codeUnit <= 0x4DBF);
  }

  /// Whether a Unicode code unit is katakana.
  static bool _isKatakana(int codeUnit) {
    return codeUnit >= 0x30A0 && codeUnit <= 0x30FF;
  }

  /// Convert a single katakana code unit to hiragana.
  static int _kataToHira(int codeUnit) {
    if (codeUnit >= 0x30A1 && codeUnit <= 0x30F6) {
      return codeUnit - 0x60;
    }
    return codeUnit;
  }

  /// Format expression + reading into Anki Japanese addon furigana notation.
  ///
  /// Example: expression="血液" reading="ケツエキ" → "血[けつ]液[えき]"
  /// Example: expression="食べる" reading="タベル" → "食[た]べる"
  ///
  /// The algorithm walks through the expression and reading in parallel:
  /// - Non-kanji characters in the expression are emitted as-is and the
  ///   corresponding characters in the reading are consumed (skipped).
  /// - Consecutive kanji characters form a "kanji run". The furigana for
  ///   the run is determined by finding where the next non-kanji expression
  ///   characters match in the remaining reading. The reading segment
  ///   between the current position and that match is the furigana.
  static String _formatFurigana(AnkiNoteData noteData) {
    final expression = noteData.expression;
    final reading = noteData.reading;

    if (reading.isEmpty || expression == reading) return expression;

    // Check if expression contains any kanji at all
    final hasKanji = expression.runes.any(_isKanji);
    if (!hasKanji) return expression;

    final hiraganaReading =
        RomajiConverter.katakanaToHiragana(reading);

    final buf = StringBuffer();
    int ri = 0; // reading index

    int i = 0;
    while (i < expression.length) {
      final char = expression[i];
      final code = char.codeUnitAt(0);

      if (!_isKanji(code)) {
        // Non-kanji: emit as-is and advance reading past matching char
        buf.write(char);
        if (ri < hiraganaReading.length) {
          // The expression char should match the reading char (both kana).
          // Advance reading pointer.
          ri++;
        }
        i++;
      } else {
        // Kanji run: find the end of consecutive kanji
        final kanjiStart = i;
        while (i < expression.length &&
            _isKanji(expression[i].codeUnitAt(0))) {
          i++;
        }
        final kanjiRun = expression.substring(kanjiStart, i);

        // Determine furigana: find where the next non-kanji expression
        // characters match in the remaining reading.
        if (i < expression.length) {
          // There are characters after the kanji run.
          // Find the next non-kanji character(s) from the expression and
          // locate them in the reading to determine the boundary.
          final nextExprChar = expression[i];
          final nextExprHira = _isKatakana(nextExprChar.codeUnitAt(0))
              ? String.fromCharCode(_kataToHira(nextExprChar.codeUnitAt(0)))
              : nextExprChar;

          // Search for the matching kana in the reading from current position
          int matchPos = -1;
          for (int j = ri; j < hiraganaReading.length; j++) {
            if (hiraganaReading[j] == nextExprHira) {
              matchPos = j;
              break;
            }
          }

          if (matchPos > ri) {
            final furi = hiraganaReading.substring(ri, matchPos);
            buf.write(' $kanjiRun[$furi]');
            ri = matchPos;
          } else {
            // Fallback: can't align, emit remaining reading for this run
            buf.write(' $kanjiRun');
          }
        } else {
          // Kanji run is at the end of the expression.
          // All remaining reading is the furigana.
          if (ri < hiraganaReading.length) {
            final furi = hiraganaReading.substring(ri);
            buf.write(' $kanjiRun[$furi]');
            ri = hiraganaReading.length;
          } else {
            buf.write(' $kanjiRun');
          }
        }
      }
    }

    return buf.toString().trim();
  }
}
