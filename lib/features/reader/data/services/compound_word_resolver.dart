import 'package:flutter/foundation.dart';

import 'package:mekuru/features/dictionary/data/services/dictionary_query_service.dart';
import 'package:mekuru/features/reader/data/services/mecab_service.dart';

/// Result of compound word resolution — either a multi-token compound that
/// was found in the dictionary, or the original single-token result.
class CompoundWordResult {
  /// The surface form of the matched compound (or single token).
  final String surfaceForm;

  /// The term to use for dictionary lookup.
  /// For compounds this equals [surfaceForm]; for single tokens this is the
  /// MeCab dictionary form (base form).
  final String dictionaryForm;

  /// Concatenated reading (katakana) of all tokens in the match.
  final String reading;

  /// Sentence context (unchanged from single-token result).
  final String sentenceContext;

  /// Start offset of the match in the surrounding text.
  final int tokenStartOffset;

  /// Number of MeCab tokens that make up this match (1 = single token).
  final int tokenCount;

  const CompoundWordResult({
    required this.surfaceForm,
    required this.dictionaryForm,
    required this.reading,
    required this.sentenceContext,
    required this.tokenStartOffset,
    required this.tokenCount,
  });
}

/// Resolves the longest compound word starting from a tapped token by
/// checking progressively longer token concatenations against the dictionary.
///
/// MeCab splits Japanese text into morphemes — e.g. "類希" → "類" + "希".
/// This resolver tries "類希" first (longer match), and only falls back to
/// "類" if no dictionary entry exists for the compound.
class CompoundWordResolver {
  final DictionaryQueryService _queryService;

  /// Maximum number of consecutive tokens to combine (including the tapped
  /// token itself).
  static const int maxTokenSpan = 5;

  CompoundWordResolver(this._queryService);

  /// Given the [identification] from MeCab, try combining the tapped token
  /// with subsequent tokens and return the longest compound with a dictionary
  /// match. Falls back to the single-token result if no compound matches.
  Future<CompoundWordResult> resolve(WordIdentification identification) async {
    final tokens = identification.alignedTokens;
    final tappedIdx = identification.tappedTokenIndex;
    final singleResult = identification.result;

    // Determine the maximum span we can try.
    final maxEnd =
        (tappedIdx + maxTokenSpan).clamp(0, tokens.length);

    // Try longest candidates first (greedy longest-match).
    for (var end = maxEnd; end > tappedIdx + 1; end--) {
      final candidate = _buildCandidate(tokens, tappedIdx, end);
      if (candidate == null) continue; // non-contiguous or unaligned

      final hasMatch = await _queryService.hasMatch(candidate.surface);
      if (hasMatch) {
        debugPrint(
          '[Compound] Found compound match: "${candidate.surface}" '
          '(${end - tappedIdx} tokens)',
        );
        return CompoundWordResult(
          surfaceForm: candidate.surface,
          dictionaryForm: candidate.surface,
          reading: candidate.reading,
          sentenceContext: singleResult.sentenceContext,
          tokenStartOffset: singleResult.tokenStartOffset,
          tokenCount: end - tappedIdx,
        );
      }
    }

    // No compound match — return the single token result.
    return CompoundWordResult(
      surfaceForm: singleResult.surfaceForm,
      dictionaryForm: singleResult.dictionaryForm,
      reading: singleResult.reading,
      sentenceContext: singleResult.sentenceContext,
      tokenStartOffset: singleResult.tokenStartOffset,
      tokenCount: 1,
    );
  }

  /// Build a compound candidate from tokens[start] to tokens[end-1].
  ///
  /// Returns `null` if any token is unaligned (`startInText == -1`) or if
  /// tokens are not contiguous in the text (there is a gap between them).
  _CompoundCandidate? _buildCandidate(
    List<TokenInfo> tokens,
    int start,
    int end,
  ) {
    final surfaceBuf = StringBuffer();
    final readingBuf = StringBuffer();

    for (var i = start; i < end; i++) {
      final token = tokens[i];
      if (token.startInText < 0) return null;

      // Check contiguity: token[i] should start right where token[i-1] ends.
      if (i > start) {
        final prev = tokens[i - 1];
        final expectedStart = prev.startInText + prev.surface.length;
        if (token.startInText != expectedStart) return null;
      }

      surfaceBuf.write(token.surface);
      readingBuf.write(token.reading);
    }

    return _CompoundCandidate(
      surface: surfaceBuf.toString(),
      reading: readingBuf.toString(),
    );
  }
}

class _CompoundCandidate {
  final String surface;
  final String reading;
  const _CompoundCandidate({required this.surface, required this.reading});
}
