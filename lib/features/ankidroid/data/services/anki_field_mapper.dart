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

  /// Format expression + reading into Anki Japanese addon furigana notation.
  static String _formatFurigana(AnkiNoteData noteData) {
    return formatAnkiFurigana(noteData.expression, noteData.reading);
  }
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
String formatAnkiFurigana(String expression, String reading) {
  if (reading.isEmpty || expression == reading) return expression;

  // Check if expression contains any kanji at all
  final hasKanji = expression.runes.any(_isKanjiFuri);
  if (!hasKanji) return expression;

  final hiraganaReading = RomajiConverter.katakanaToHiragana(reading);

  final buf = StringBuffer();
  int ri = 0; // reading index

  int i = 0;
  while (i < expression.length) {
    final char = expression[i];
    final code = char.codeUnitAt(0);

    if (!_isKanjiFuri(code)) {
      // Non-kanji: emit as-is and advance reading past matching char
      buf.write(char);
      if (ri < hiraganaReading.length) {
        ri++;
      }
      i++;
    } else {
      // Kanji run: find the end of consecutive kanji
      final kanjiStart = i;
      while (i < expression.length &&
          _isKanjiFuri(expression[i].codeUnitAt(0))) {
        i++;
      }
      final kanjiRun = expression.substring(kanjiStart, i);

      if (i < expression.length) {
        final nextExprChar = expression[i];
        final nextCode = nextExprChar.codeUnitAt(0);
        final nextExprHira = (nextCode >= 0x30A1 && nextCode <= 0x30F6)
            ? String.fromCharCode(nextCode - 0x60)
            : nextExprChar;

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
          buf.write(' $kanjiRun');
        }
      } else {
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

bool _isKanjiFuri(int codeUnit) {
  return (codeUnit >= 0x4E00 && codeUnit <= 0x9FFF) ||
      (codeUnit >= 0x3400 && codeUnit <= 0x4DBF);
}
