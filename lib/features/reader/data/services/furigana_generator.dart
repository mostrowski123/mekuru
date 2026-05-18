import 'package:mekuru/features/dictionary/data/services/romaji_converter.dart';
import 'package:mekuru/features/reader/data/services/mecab_service.dart';
import 'package:mekuru/shared/widgets/furigana_text.dart';

/// Abstraction over MeCab so the generator can be unit-tested with a fake.
abstract class FuriganaTokenizer {
  List<TokenInfo> tokenize(String text);
}

class MecabFuriganaTokenizer implements FuriganaTokenizer {
  const MecabFuriganaTokenizer();

  @override
  List<TokenInfo> tokenize(String text) =>
      MecabService.instance.tokenizeForFurigana(text);
}

/// Generates per-kanji furigana annotations for batches of input strings.
///
/// For each input, the result is a `{source, segments}` map where `segments`
/// is an ordered list of `{t, f?}` entries: `t` is the literal characters and
/// `f` (when present) is the hiragana reading to render above `t` in a `<rt>`.
/// Segments concatenated together reproduce `source` exactly.
class FuriganaGenerator {
  final FuriganaTokenizer _tokenizer;

  const FuriganaGenerator(this._tokenizer);

  List<Map<String, Object?>> generate(List<String> inputs) =>
      inputs.map(_generateOne).toList(growable: false);

  Map<String, Object?> _generateOne(String input) {
    if (input.isEmpty) {
      return {'source': input, 'segments': const <Map<String, Object?>>[]};
    }

    final tokens = _tokenizer.tokenize(input);
    if (tokens.isEmpty) {
      return {
        'source': input,
        'segments': [
          {'t': input},
        ],
      };
    }

    final segments = <Map<String, Object?>>[];
    var cursor = 0;

    for (final token in tokens) {
      if (token.startInText > cursor) {
        segments.add({'t': input.substring(cursor, token.startInText)});
      }

      if (token.reading.isEmpty) {
        segments.add({'t': token.surface});
      } else {
        final hira = RomajiConverter.katakanaToHiragana(token.reading);
        final segs = segmentFurigana(token.surface, hira);
        for (final s in segs) {
          if (s.furigana == null) {
            segments.add({'t': s.text});
          } else {
            segments.add({'t': s.text, 'f': s.furigana});
          }
        }
      }

      cursor = token.startInText + token.surface.length;
    }

    if (cursor < input.length) {
      segments.add({'t': input.substring(cursor)});
    }

    return {'source': input, 'segments': segments};
  }
}
