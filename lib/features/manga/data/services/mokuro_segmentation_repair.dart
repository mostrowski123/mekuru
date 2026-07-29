import '../models/mokuro_models.dart';

/// Pure heuristics deciding when a mokuro page cache needs MeCab word
/// segmentation (again). Flutter-free so it stays unit-testable.

/// Matches characters MeCab reliably segments and annotates: kana, kanji,
/// and the 々/〆 marks. Deliberately excludes standalone ー and ゝゞヽヾ,
/// which can survive as unannotated unknown tokens even with MeCab up.
final _japaneseWordChar = RegExp(
  r'[々〆ぁ-ゖァ-ヺ㐀-䶿一-鿿]',
);

/// Whether [pages] contain any block that still needs word segmentation.
bool pagesNeedWordSegmentation(List<MokuroPage> pages) =>
    pages.any(pageNeedsWordSegmentation);

/// Whether [page] has any block that still needs word segmentation: either
/// never segmented (lines but no words) or carrying the broken output of a
/// segmentation run against an uninitialized MeCab.
bool pageNeedsWordSegmentation(MokuroPage page) {
  for (final block in page.blocks) {
    if (block.lines.isNotEmpty && block.words.isEmpty) return true;
    if (blockHasBrokenWordSegmentation(block)) return true;
  }
  return false;
}

/// Whether [block] carries the signature of segmentation that ran while
/// MeCab was uninitialized: `tokenize()` falls back to the whole line as a
/// single token and `identifyWordWithContext()` returns null, producing one
/// line-spanning word with neither dictionary form nor reading. A healthy
/// run always sets a dictionary form on words with Japanese content, so
/// this cannot match correctly segmented blocks (and repairing is therefore
/// a one-shot fix, not a rewrite-on-every-load loop).
bool blockHasBrokenWordSegmentation(MokuroTextBlock block) {
  for (final word in block.words) {
    if (word.dictionaryForm != null || word.reading != null) continue;
    if (word.charStartInLine != 0) continue;
    if (word.lineIndex < 0 || word.lineIndex >= block.lines.length) continue;
    if (word.surface != block.lines[word.lineIndex]) continue;
    if (!_japaneseWordChar.hasMatch(word.surface)) continue;
    return true;
  }
  return false;
}
