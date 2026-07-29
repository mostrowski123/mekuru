import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/utils/japanese_text.dart';

/// Each helper replaced a privately maintained per-site definition. The
/// `legacy` closures below transcribe the deleted boolean expressions
/// verbatim, and every predicate is swept over the whole BMP (plus
/// supplementary samples) to prove the shared helper is bit-identical to
/// what each call site used before the extraction.

// Code points swept for equivalence: the full BMP minus the surrogate
// block, plus supplementary-plane samples (a CJK Extension B kanji, an
// emoji) that reach the predicates as single rune values.
Iterable<int> _sweep() sync* {
  for (var cp = 0; cp <= 0xFFFF; cp++) {
    if (cp >= 0xD800 && cp <= 0xDFFF) continue;
    yield cp;
  }
  yield 0x20000; // 𠀀 CJK Extension B
  yield 0x1F600; // 😀
}

void _expectMatchesLegacy(
  bool Function(int) actual,
  bool Function(int) legacy,
) {
  for (final cp in _sweep()) {
    expect(actual(cp), legacy(cp), reason: 'U+${cp.toRadixString(16)}');
  }
}

bool _matchesSingleChar(RegExp pattern, int cp) =>
    pattern.hasMatch(String.fromCharCode(cp));

void main() {
  group('isKanji', () {
    test('matches the ranges the five strict-kanji sites used', () {
      // anki_field_mapper._isKanjiFuri, dictionary_search_screen._isCjk,
      // tappable_expression_text._isKanji, dictionary_query_service._isKanji,
      // kanji_reading_parser._isSingleKanji.
      _expectMatchesLegacy(
        isKanji,
        (cp) =>
            (cp >= 0x4E00 && cp <= 0x9FFF) || (cp >= 0x3400 && cp <= 0x4DBF),
      );
    });

    test('excludes the marks 々〆ヵヶ and all kana', () {
      expect(isKanji(0x3005), isFalse); // 々
      expect(isKanji(0x3006), isFalse); // 〆
      expect(isKanji(0x30F5), isFalse); // ヵ
      expect(isKanji(0x30F6), isFalse); // ヶ
      expect(isKanji('あ'.runes.single), isFalse);
      expect(isKanji('ア'.runes.single), isFalse);
      expect(isKanji('漢'.runes.single), isTrue);
      expect(isKanji('㐀'.runes.single), isTrue); // Extension A start
    });
  });

  group('isKanjiForFurigana', () {
    test('matches furigana_text._isKanji exactly', () {
      _expectMatchesLegacy(
        isKanjiForFurigana,
        (cp) =>
            (cp >= 0x4E00 && cp <= 0x9FFF) ||
            (cp >= 0x3400 && cp <= 0x4DBF) ||
            cp == 0x3005 || // 々 iteration mark
            cp == 0x3006 || // 〆
            cp == 0x30F5 || // ヵ
            cp == 0x30F6, // ヶ
      );
    });
  });

  group('isKana', () {
    test('matches dictionary_query_service._isKanaRune exactly', () {
      _expectMatchesLegacy(
        isKana,
        (cp) =>
            (cp >= 0x3040 && cp <= 0x309F) ||
            (cp >= 0x30A0 && cp <= 0x30FF) ||
            cp == 0x30FC,
      );
    });
  });

  group('isKatakana', () {
    test('matches kanji_reading_parser katakana-token check exactly', () {
      _expectMatchesLegacy(
        isKatakana,
        (cp) => (cp >= 0x30A0 && cp <= 0x30FF) || cp == 0x30FC,
      );
    });
  });

  group('isHiragana', () {
    test('matches the hiragana part of the hiragana-token check', () {
      _expectMatchesLegacy(
        isHiragana,
        (cp) => (cp >= 0x3040 && cp <= 0x309F) || cp == 0x30FC,
      );
    });

    test('leaves the kanjidic okurigana dot to the call site', () {
      // kanji_reading_parser._isHiraganaReadingToken also accepts U+002E;
      // that stays there as `|| rune == 0x002E`.
      expect(isHiragana(0x002E), isFalse);
    });
  });

  group('japaneseRunPattern', () {
    test('accepts exactly the characters the original pattern did', () {
      // tappable_definition_text._japanesePattern: hiragana, katakana, CJK,
      // Extension A, plus explicit U+30FC (redundant: inside the katakana
      // block) and U+3005.
      _expectMatchesLegacy(
        (cp) => _matchesSingleChar(japaneseRunPattern, cp),
        (cp) =>
            (cp >= 0x3040 && cp <= 0x309F) ||
            (cp >= 0x30A0 && cp <= 0x30FF) ||
            (cp >= 0x4E00 && cp <= 0x9FFF) ||
            (cp >= 0x3400 && cp <= 0x4DBF) ||
            cp == 0x30FC ||
            cp == 0x3005,
      );
    });

    test('splits mixed text into Japanese runs', () {
      const text = 'Learn 日本語 with ふりがな, カタカナー, 々, and 〆 or ヵヶ… definitions!';
      final runs = japaneseRunPattern
          .allMatches(text)
          .map((m) => m.group(0)!)
          .toList();
      // 〆 (U+3006) is not part of the run pattern's character class.
      expect(runs, ['日本語', 'ふりがな', 'カタカナー', '々', 'ヵヶ']);
    });
  });

  group('mecabAnnotatedCharPattern', () {
    test('accepts exactly the characters the original pattern did', () {
      // mokuro_segmentation_repair._japaneseWordChar: 々〆, ぁ-ゖ, ァ-ヺ,
      // Extension A, CJK.
      _expectMatchesLegacy(
        (cp) => _matchesSingleChar(mecabAnnotatedCharPattern, cp),
        (cp) =>
            cp == 0x3005 || // 々
            cp == 0x3006 || // 〆
            (cp >= 0x3041 && cp <= 0x3096) || // ぁ-ゖ
            (cp >= 0x30A1 && cp <= 0x30FA) || // ァ-ヺ
            (cp >= 0x3400 && cp <= 0x4DBF) ||
            (cp >= 0x4E00 && cp <= 0x9FFF),
      );
    });

    test('still excludes the marks the repair heuristic relies on', () {
      expect(mecabAnnotatedCharPattern.hasMatch('ー'), isFalse);
      expect(mecabAnnotatedCharPattern.hasMatch('ゝ'), isFalse);
      expect(mecabAnnotatedCharPattern.hasMatch('ゞ'), isFalse);
      expect(mecabAnnotatedCharPattern.hasMatch('ヽ'), isFalse);
      expect(mecabAnnotatedCharPattern.hasMatch('ヾ'), isFalse);
      expect(mecabAnnotatedCharPattern.hasMatch('々'), isTrue);
      expect(mecabAnnotatedCharPattern.hasMatch('〆'), isTrue);
    });
  });
}
