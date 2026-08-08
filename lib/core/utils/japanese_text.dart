/// Shared Unicode character classes and conversions for Japanese text.
/// Pure Dart (Flutter-free) so pure-logic services can use it and it stays
/// unit-testable.
///
/// The predicates deliberately differ in how inclusive "Japanese" is —
/// pick the one whose documented semantics match the call site instead of
/// widening an existing one.
library;

import 'jlpt_kanji_levels.dart';

/// Kanji in the strict sense: CJK Unified Ideographs (U+4E00–U+9FFF) and
/// Extension A (U+3400–U+4DBF). Marks like 々 are excluded.
bool isKanji(int rune) =>
    (rune >= 0x4E00 && rune <= 0x9FFF) || (rune >= 0x3400 && rune <= 0x4DBF);

/// Characters that carry a reading during furigana alignment: kanji plus
/// 々 (U+3005), 〆 (U+3006), ヵ (U+30F5), and ヶ (U+30F6).
///
/// Not every furigana path uses this: the Anki furigana exporter
/// deliberately treats only strict [isKanji] runs as reading-bearing.
bool isKanjiForFurigana(int rune) =>
    isKanji(rune) ||
    rune == 0x3005 ||
    rune == 0x3006 ||
    rune == 0x30F5 ||
    rune == 0x30F6;

/// Hiragana (U+3040–U+309F) or katakana (U+30A0–U+30FF, which includes the
/// prolonged sound mark ー U+30FC).
bool isKana(int rune) =>
    (rune >= 0x3040 && rune <= 0x309F) || (rune >= 0x30A0 && rune <= 0x30FF);

/// Katakana (U+30A0–U+30FF, which includes the prolonged sound mark ー).
bool isKatakana(int rune) => rune >= 0x30A0 && rune <= 0x30FF;

/// Hiragana (U+3040–U+309F) or the prolonged sound mark ー (U+30FC), which
/// also appears in hiragana words (らーめん).
bool isHiragana(int rune) =>
    (rune >= 0x3040 && rune <= 0x309F) || rune == 0x30FC;

/// Convert a katakana rune (U+30A1–U+30F6) to hiragana by the −0x60 offset;
/// any other rune — including the prolonged sound mark ー (U+30FC) — is
/// returned unchanged.
int katakanaRuneToHiragana(int rune) =>
    (rune >= 0x30A1 && rune <= 0x30F6) ? rune - 0x60 : rune;

/// Convert katakana in [text] to hiragana; see [katakanaRuneToHiragana]
/// for the per-rune rule.
String katakanaToHiragana(String text) {
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    buffer.writeCharCode(katakanaRuneToHiragana(rune));
  }
  return buffer.toString();
}

/// Matches runs of Japanese text: hiragana (U+3040–U+309F), katakana
/// (U+30A0–U+30FF, including ー), kanji (CJK Unified Ideographs and
/// Extension A), and the iteration mark 々 (U+3005).
final RegExp japaneseRunPattern = RegExp(
  r'[\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FFF\u3400-\u4DBF\u3005]+',
);

/// Matches a single character MeCab reliably segments and annotates: kana,
/// kanji, and the 々/〆 marks. Deliberately narrower than
/// [japaneseRunPattern]: it excludes the standalone prolonged sound mark ー
/// and the iteration marks ゝゞヽヾ, which can survive as unannotated
/// unknown tokens even with MeCab up, so segmentation-repair heuristics
/// must not treat them as evidence of healthy Japanese output.
final RegExp mecabAnnotatedCharPattern = RegExp(r'[々〆ぁ-ゖァ-ヺ㐀-䶿一-鿿]');

/// Whether [surface] contains a kanji harder than JLPT [level] (5 = N5 …
/// 1 = N1). Kanji absent from [jlptKanjiLevel] are non-joyo and count as
/// the hardest (0); the repetition mark 々 inherits the preceding kanji.
/// The whole word qualifies when ANY of its kanji is above the threshold,
/// so mixed-level words keep their furigana readable end to end.
bool wordNeedsFuriganaAboveLevel(String surface, int level) {
  int? previousLevel;
  for (final rune in surface.runes) {
    if (!isKanjiForFurigana(rune)) {
      previousLevel = null;
      continue;
    }
    final runeLevel = rune == 0x3005
        ? (previousLevel ?? 0)
        : (jlptKanjiLevel[rune] ?? 0);
    previousLevel = runeLevel;
    if (runeLevel < level) return true;
  }
  return false;
}
