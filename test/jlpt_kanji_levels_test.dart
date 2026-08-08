import 'package:flutter_test/flutter_test.dart';
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

  test('off-list kanji count as hardest', () {
    expect(wordNeedsFuriganaAboveLevel('龘', 5), isTrue);
  });

  test('repetition mark inherits the preceding kanji level', () {
    // 人 is N5, so 人々 needs no furigana above N3 even though 々 itself
    // has no JLPT level.
    expect(wordNeedsFuriganaAboveLevel('人々', 3), isFalse);
  });
}
