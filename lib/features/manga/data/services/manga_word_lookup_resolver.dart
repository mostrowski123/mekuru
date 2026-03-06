import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/reader/data/services/compound_word_resolver.dart';
import 'package:mekuru/features/reader/data/services/mecab_service.dart';

typedef IdentifyMangaWord =
    WordIdentification? Function(String text, int charOffset);
typedef ResolveMangaCompoundWord =
    Future<CompoundWordResult> Function(WordIdentification identification);

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

  Future<WordLookupResult> resolve(
    MokuroWord word,
    MokuroTextBlock block,
  ) async {
    final lookupContext = _buildLookupContext(word, block);
    if (lookupContext == null) {
      return _fallbackResult(word, blockText: '', tokenStartOffset: 0);
    }

    final identification = _identifyWordWithContext(
      lookupContext.text,
      lookupContext.charOffset,
    );
    if (identification == null) {
      return _fallbackResult(
        word,
        blockText: lookupContext.text,
        tokenStartOffset: lookupContext.charOffset,
      );
    }

    final compound = await _resolveCompoundWord(identification);
    return WordLookupResult(
      surfaceForm: compound.surfaceForm,
      dictionaryForm: compound.dictionaryForm,
      reading: compound.reading,
      sentenceContext: compound.sentenceContext,
      tokenStartOffset: compound.tokenStartOffset,
    );
  }

  _MangaLookupContext? _buildLookupContext(
    MokuroWord word,
    MokuroTextBlock block,
  ) {
    if (block.lines.isEmpty ||
        word.lineIndex < 0 ||
        word.lineIndex >= block.lines.length) {
      return null;
    }

    final text = block.fullText;
    var charOffset = 0;
    for (var i = 0; i < word.lineIndex; i++) {
      charOffset += block.lines[i].length;
    }
    charOffset += word.charStartInLine;

    if (text.isEmpty || charOffset < 0 || charOffset >= text.length) {
      return null;
    }

    return _MangaLookupContext(text: text, charOffset: charOffset);
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
