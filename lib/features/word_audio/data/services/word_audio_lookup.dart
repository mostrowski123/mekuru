import 'package:convert/convert.dart' show hex;
import 'package:mekuru/core/utils/japanese_text.dart';
import 'package:mekuru/features/dictionary/data/services/glossary_parser.dart';
import 'package:mekuru/features/dictionary/data/services/romaji_converter.dart';
import 'package:sqlite3/sqlite3.dart';

/// The word list of the hosted audio: which clip speaks a dictionary entry.
/// A read-only sqlite file with one table, `pair(expression, reading, id,
/// score)`, outside Drift so its 300,000 rows stay out of the main database
/// and every full backup.
class WordAudioIndex {
  WordAudioIndex.open(String path)
    : _db = sqlite3.open(path, mode: OpenMode.readOnly);

  final Database _db;

  /// The clip id for an entry, or null when no clip fits.
  ///
  /// Spellings JMdict files under another word (だけ under 丈) and old-kanji
  /// rows that only redirect ("⟶ 労働相") reach a clip here. A spelling the
  /// list doesn't know only gets a clip when its reading has just one: a
  /// homophone would speak the wrong accent.
  String? clipFor(String expression, String reading, {String glossaries = ''}) {
    // The usual hit first: every result in a list asks, and parsing its
    // glossary to look for a redirect is the slow part.
    if (reading.isNotEmpty) {
      final clip = _pair(expression, reading);
      if (clip != null) return clip;
    }
    if (GlossaryParser.redirectTarget(glossaries) case final target?) {
      expression = target.expression;
      reading = target.reading;
      if (reading.isNotEmpty) {
        final clip = _pair(expression, reading);
        if (clip != null) return clip;
      }
    }
    if (reading.isEmpty) {
      final clip = _first(
        'SELECT id FROM pair WHERE expression = ? ORDER BY score DESC LIMIT 1',
        [expression],
      );
      if (clip != null) return clip;
    }
    if (expression.runes.every(isKana)) {
      final kana = _kanaForms(expression);
      final clip = _first(
        'SELECT id FROM pair WHERE reading IN (${_marks(kana)}) '
        'ORDER BY score DESC LIMIT 1',
        kana,
      );
      if (clip != null) return clip;
    }
    if (reading.isEmpty) return null;
    final kana = _kanaForms(reading);
    final clips = _db.select(
      'SELECT DISTINCT id FROM pair WHERE reading IN (${_marks(kana)}) LIMIT 2',
      kana,
    );
    return clips.length == 1 ? _hex(clips.first) : null;
  }

  void close() => _db.close();

  String? _pair(String expression, String reading) {
    final kana = _kanaForms(reading);
    return _first(
      'SELECT id FROM pair WHERE expression = ? '
      'AND reading IN (${_marks(kana)}) LIMIT 1',
      [expression, ...kana],
    );
  }

  String? _first(String sql, List<String> args) {
    final rows = _db.select(sql, args);
    return rows.isEmpty ? null : _hex(rows.first);
  }

  static List<String> _kanaForms(String kana) => {
    kana,
    katakanaToHiragana(kana),
    RomajiConverter.hiraganaToKatakana(kana),
  }.toList();

  static String _marks(List<String> args) =>
      List.filled(args.length, '?').join(',');

  static String _hex(Row row) => hex.encode(row['id'] as List<int>);
}
