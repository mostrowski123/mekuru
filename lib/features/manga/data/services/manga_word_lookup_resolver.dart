import 'dart:ui' show Rect;

import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/data/services/mokuro_block_geometry.dart';
import 'package:mekuru/features/reader/data/services/compound_word_resolver.dart';
import 'package:mekuru/features/reader/data/services/mecab_service.dart';

typedef IdentifyMangaWord =
    WordIdentification? Function(String text, int charOffset);
typedef ResolveMangaCompoundWord =
    Future<CompoundWordResult> Function(WordIdentification identification);

/// A resolved manga lookup plus the image-space rectangles the highlight
/// should cover so it matches the word that was actually looked up.
class MangaWordLookup {
  final WordLookupResult result;

  /// Rect(s) covering the resolved word in image pixels, one per OCR line
  /// the word spans. Falls back to the tapped word's own bounding box when
  /// the resolved span could not be mapped onto the block.
  final List<Rect> highlightRects;

  const MangaWordLookup({required this.result, required this.highlightRects});
}

/// Resolves manga OCR taps to the longest dictionary match available.
///
/// The OCR overlay stores individual word boxes, but the lookup should still
/// consider the surrounding block text so compounds like "どうしたの" win over
/// the tapped sub-token "どう" when the dictionary contains the longer entry.
class MangaWordLookupResolver {
  final IdentifyMangaWord _identifyWordWithContext;
  final ResolveMangaCompoundWord _resolveCompoundWord;

  const MangaWordLookupResolver({
    required IdentifyMangaWord identifyWordWithContext,
    required ResolveMangaCompoundWord resolveCompoundWord,
  }) : _identifyWordWithContext = identifyWordWithContext,
       _resolveCompoundWord = resolveCompoundWord;

  Future<MangaWordLookup> resolve(
    MokuroWord word,
    MokuroTextBlock block,
  ) async {
    final lookupContext = _buildLookupContext(word, block);
    if (lookupContext == null) {
      return MangaWordLookup(
        result: _fallbackResult(word, blockText: '', tokenStartOffset: 0),
        highlightRects: [word.boundingBox],
      );
    }

    final identification = _identifyWordWithContext(
      lookupContext.text,
      lookupContext.charOffset,
    );
    if (identification == null) {
      return MangaWordLookup(
        result: _fallbackResult(
          word,
          blockText: lookupContext.text,
          tokenStartOffset: lookupContext.charOffset,
        ),
        highlightRects: [word.boundingBox],
      );
    }

    final compound = await _resolveCompoundWord(identification);
    return MangaWordLookup(
      result: WordLookupResult(
        surfaceForm: compound.surfaceForm,
        dictionaryForm: compound.dictionaryForm,
        reading: compound.reading,
        sentenceContext: compound.sentenceContext,
        tokenStartOffset: compound.tokenStartOffset,
      ),
      highlightRects: _highlightRects(word, block, lookupContext, compound),
    );
  }

  /// Map the resolved compound's span onto the block's line quads.
  ///
  /// `tokenStartOffset` comes from MeCab, whose offsets are in sanitized
  /// coordinates (invisible characters stripped). The span is only trusted
  /// when it really spells the resolved surface form in the block's own
  /// text; otherwise the tapped word's box is kept. Deliberately no recovery
  /// search — a missing highlight refinement beats a wrongly placed one.
  static List<Rect> _highlightRects(
    MokuroWord word,
    MokuroTextBlock block,
    _MangaLookupContext lookupContext,
    CompoundWordResult compound,
  ) {
    final text = lookupContext.text;
    final surfaceForm = compound.surfaceForm;
    final start = compound.tokenStartOffset;
    final end = start + surfaceForm.length;
    if (surfaceForm.isNotEmpty &&
        start >= 0 &&
        end <= text.length &&
        text.substring(start, end) == surfaceForm) {
      final rects = blockCharRangeRects(block, start, end);
      if (rects.isNotEmpty) return rects;
    }
    return [word.boundingBox];
  }

  _MangaLookupContext? _buildLookupContext(
    MokuroWord word,
    MokuroTextBlock block,
  ) {
    final charOffset = blockCharOffset(
      block,
      word.lineIndex,
      word.charStartInLine,
    );
    if (charOffset == null) return null;
    return _MangaLookupContext(text: block.fullText, charOffset: charOffset);
  }

  WordLookupResult _fallbackResult(
    MokuroWord word, {
    required String blockText,
    required int tokenStartOffset,
  }) {
    final sentenceContext = blockText.isEmpty ? word.surface : blockText;
    return WordLookupResult(
      surfaceForm: word.surface,
      dictionaryForm: word.dictionaryForm ?? word.surface,
      reading: word.reading ?? '',
      sentenceContext: sentenceContext,
      tokenStartOffset: tokenStartOffset,
    );
  }
}

class _MangaLookupContext {
  final String text;
  final int charOffset;

  const _MangaLookupContext({required this.text, required this.charOffset});
}
