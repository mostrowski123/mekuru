import 'package:flutter/foundation.dart';

import 'package:mekuru/features/dictionary/data/services/dictionary_query_service.dart';
import 'package:mekuru/features/reader/data/services/deinflection.dart';
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
    final maxEnd = (tappedIdx + maxTokenSpan).clamp(0, tokens.length);

    // Build the ordered list of candidate checks, longest span first and —
    // within a span — exact surface before deinflected forms. This is the
    // exact order the legacy per-call loop walked, so whichever path we take
    // below picks the same winning candidate.
    final checks = <_CompoundCheck>[];
    for (var end = maxEnd; end > tappedIdx + 1; end--) {
      final candidate = _buildCandidate(tokens, tappedIdx, end);
      if (candidate == null) continue;
      final tokenCount = end - tappedIdx;
      checks.add(_CompoundCheck(
        candidate: candidate,
        dictionaryForm: candidate.surface,
        tokenCount: tokenCount,
        isDeinflection: false,
      ));
      for (final d in deinflect(candidate.surface)) {
        checks.add(_CompoundCheck(
          candidate: candidate,
          dictionaryForm: d,
          tokenCount: tokenCount,
          isDeinflection: true,
        ));
      }
    }

    if (checks.isEmpty) {
      return _singleTokenFallback(singleResult);
    }

    _CompoundCheck? winner;
    if (kUseBatchedDictionaryLookup) {
      // Single SQL round-trip covering every candidate.
      final terms = <String>[for (final c in checks) c.dictionaryForm];
      final matched = await _queryService.matchingTerms(terms);
      for (final check in checks) {
        if (matched.contains(check.dictionaryForm)) {
          winner = check;
          break;
        }
      }
    } else {
      // Legacy path: one SQL round-trip per candidate.
      for (final check in checks) {
        if (await _queryService.hasMatch(check.dictionaryForm)) {
          winner = check;
          break;
        }
      }
    }

    if (winner != null) {
      if (winner.isDeinflection) {
        debugPrint(
          '[Compound] Found deinflected compound match: '
          '"${winner.candidate.surface}" → "${winner.dictionaryForm}" '
          '(${winner.tokenCount} tokens)',
        );
      } else {
        debugPrint(
          '[Compound] Found compound match: "${winner.candidate.surface}" '
          '(${winner.tokenCount} tokens)',
        );
      }
      return CompoundWordResult(
        surfaceForm: winner.candidate.surface,
        dictionaryForm: winner.dictionaryForm,
        reading: winner.candidate.reading,
        sentenceContext: singleResult.sentenceContext,
        tokenStartOffset: singleResult.tokenStartOffset,
        tokenCount: winner.tokenCount,
      );
    }

    return _singleTokenFallback(singleResult);
  }

  CompoundWordResult _singleTokenFallback(WordLookupResult singleResult) {
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

class _CompoundCheck {
  final _CompoundCandidate candidate;
  final String dictionaryForm;
  final int tokenCount;
  final bool isDeinflection;
  const _CompoundCheck({
    required this.candidate,
    required this.dictionaryForm,
    required this.tokenCount,
    required this.isDeinflection,
  });
}
