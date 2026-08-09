import 'package:mekuru/core/utils/japanese_text.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/data/services/mecab_service.dart';
import 'package:mekuru/shared/widgets/furigana_text.dart';

/// The real-MeCab generator preconfigured for [mode]:
/// [FuriganaMode.aboveLevel] skips words with no kanji above the JLPT
/// threshold, every other generating mode annotates everything. Shared by
/// the reader's webview handler and the EPUB exporter.
FuriganaGenerator furiganaGeneratorFor(FuriganaMode mode, int jlptLevel) {
  return FuriganaGenerator(
    const MecabFuriganaTokenizer(),
    skipToken: mode == FuriganaMode.aboveLevel
        ? (token) => !wordNeedsFuriganaAboveLevel(token.surface, jlptLevel)
        : null,
  );
}

/// The authored-ruby policy paired with [furiganaGeneratorFor]:
/// [FuriganaMode.aboveLevel] strips publisher ruby whose base has no kanji
/// above the JLPT threshold, every other mode leaves it alone (null).
/// Kept beside the generator factory so the two halves of the aboveLevel
/// filter cannot be derived from different mode/level pairs.
bool Function(String baseText)? authoredRubyStripFor(
  FuriganaMode mode,
  int jlptLevel,
) => mode == FuriganaMode.aboveLevel
    ? ((base) => !wordNeedsFuriganaAboveLevel(base, jlptLevel))
    : null;

/// Abstraction over MeCab so the generator can be unit-tested with a fake.
abstract class FuriganaTokenizer {
  /// Brings the tokenizer up if needed; `false` when it cannot come up.
  Future<bool> ensureReady();

  List<TokenInfo> tokenize(String text);
}

class MecabFuriganaTokenizer implements FuriganaTokenizer {
  const MecabFuriganaTokenizer();

  @override
  Future<bool> ensureReady() async {
    // Furigana readings only need IPADIC (see [MecabService.init] on the
    // flag).
    final ready = await MecabService.instance.ensureInitialized(
      upgradeToEnhanced: false,
    );
    if (!ready) return false;
    // Wait out any in-flight UniDic-lite upgrade: the JS bridge caches
    // annotations for the whole webview session, so generating mid-swap
    // would pin pre-upgrade readings past the swap.
    await MecabService.instance.settledLayout();
    return true;
  }

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

  /// When set and returning true for a token, that token is emitted as bare
  /// text with no reading — the hook for coverage filters like
  /// "only kanji above the reader's JLPT level".
  final bool Function(TokenInfo token)? skipToken;

  const FuriganaGenerator(this._tokenizer, {this.skipToken});

  /// Returns null when the tokenizer cannot be brought up, so the JS bridge
  /// can tell "tokenizer unavailable" apart from "no readings found" and skip
  /// caching. Without this gate, annotations generated while MeCab was still
  /// initializing (plain text, no readings) would be cached as successes for
  /// the rest of the webview session.
  Future<List<Map<String, Object?>>?> generate(List<String> inputs) async {
    if (!await _tokenizer.ensureReady()) return null;
    return inputs.map(_generateOne).toList(growable: false);
  }

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

      if (token.reading.isEmpty || (skipToken?.call(token) ?? false)) {
        segments.add({'t': token.surface});
      } else {
        final hira = katakanaToHiragana(token.reading);
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
