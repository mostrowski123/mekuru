import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/utils/japanese_text.dart';
import 'package:mekuru/core/utils/jlpt_kanji_levels.dart';

void main() {
  test('map anchors: N5 and N1 kanji have expected levels', () {
    expect(jlptKanjiLevel['一'.runes.single], 5);
    expect(jlptKanjiLevel['人'.runes.single], 5);
    expect(jlptKanjiLevel['憂'.runes.single], 1);
    expect(jlptKanjiLevel.length, greaterThan(2000));
  });

  test('kana-only words never need furigana', () {
    expect(wordNeedsFuriganaAboveLevel('かな', 1), isFalse);
    expect(wordNeedsFuriganaAboveLevel('カナ', 5), isFalse);
    expect(wordNeedsFuriganaAboveLevel('', 5), isFalse);
  });

  test('easy words stay bare, hard words qualify', () {
    expect(wordNeedsFuriganaAboveLevel('一', 3), isFalse);
    // "Above N5" means harder than N5, so an N5 kanji stays bare even there.
    expect(wordNeedsFuriganaAboveLevel('一', 5), isFalse);
    expect(wordNeedsFuriganaAboveLevel('憂鬱', 3), isTrue);
  });

  test('mixed-level word qualifies as a whole when any kanji is above', () {
    // N1 kanji next to an N5 kanji: the whole word gets furigana above N3.
    expect(wordNeedsFuriganaAboveLevel('憂一', 3), isTrue);
  });

  test('2010 joyo additions with common vocab use their word level', () {
    // 誰 (だれ, N5 word) and 頃 (〜頃, N5 grammar) predate no JLPT kanji
    // list — the lists predate the 2010 joyo reform — so without overrides
    // they would count as hardest and get furigana at every threshold.
    expect(wordNeedsFuriganaAboveLevel('誰', 1), isFalse);
    expect(wordNeedsFuriganaAboveLevel('誰', 5), isFalse);
    expect(wordNeedsFuriganaAboveLevel('頃', 4), isFalse);
    expect(wordNeedsFuriganaAboveLevel('喉', 3), isFalse);
  });

  test('joyo kanji missing from the lists count as N1, not hardest', () {
    // 鬱 is a 2010 joyo addition with no beginner vocabulary: bare at
    // "above N1", annotated below.
    expect(wordNeedsFuriganaAboveLevel('鬱', 1), isFalse);
    expect(wordNeedsFuriganaAboveLevel('鬱', 2), isTrue);
  });

  test('non-joyo kanji count as hardest', () {
    expect(wordNeedsFuriganaAboveLevel('龘', 5), isTrue);
    // Annotated even at the strictest threshold.
    expect(wordNeedsFuriganaAboveLevel('龘', 1), isTrue);
  });

  test('repetition mark inherits the preceding kanji level', () {
    // 人 is N5, so 人々 needs no furigana above N3 even though 々 itself
    // has no JLPT level.
    expect(wordNeedsFuriganaAboveLevel('人々', 3), isFalse);
  });
}
