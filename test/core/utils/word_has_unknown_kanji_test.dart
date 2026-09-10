import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/utils/japanese_text.dart';

Set<int> _runes(String kanji) => kanji.runes.toSet();

void main() {
  group('wordHasUnknownKanji', () {
    test('kana-only and empty words never qualify', () {
      expect(wordHasUnknownKanji('かな', const {}), isFalse);
      expect(wordHasUnknownKanji('カナ', const {}), isFalse);
      expect(wordHasUnknownKanji('', const {}), isFalse);
      expect(wordHasUnknownKanji('abc 123', const {}), isFalse);
    });

    test('a word made only of known kanji stays bare', () {
      expect(wordHasUnknownKanji('日本', _runes('日本')), isFalse);
      expect(wordHasUnknownKanji('食べる', _runes('食')), isFalse);
    });

    test('one unknown kanji flags the whole word', () {
      expect(wordHasUnknownKanji('日本語', _runes('日本')), isTrue);
      expect(wordHasUnknownKanji('語', _runes('日本')), isTrue);
    });

    test('an empty known set means every kanji is unknown', () {
      expect(wordHasUnknownKanji('日', const {}), isTrue);
    });

    test('repetition mark inherits the preceding kanji', () {
      expect(wordHasUnknownKanji('人々', _runes('人')), isFalse);
      expect(wordHasUnknownKanji('人々', const {}), isTrue);
      // A leading 々 has nothing to inherit and is ignored.
      expect(wordHasUnknownKanji('々', const {}), isFalse);
    });

    test('inheritance does not cross kana', () {
      // 々 after kana inherits nothing, so it neither flags nor clears.
      expect(wordHasUnknownKanji('日の々', _runes('日')), isFalse);
    });

    test('counter marks and 〆 are ignored', () {
      expect(wordHasUnknownKanji('一ヶ月', _runes('一月')), isFalse);
      expect(wordHasUnknownKanji('一ヵ所', _runes('一所')), isFalse);
      expect(wordHasUnknownKanji('〆切', _runes('切')), isFalse);
      // The kanji beside them still count.
      expect(wordHasUnknownKanji('一ヶ月', _runes('一')), isTrue);
    });

    test('extension A kanji count as kanji', () {
      const extA = 0x3400;
      expect(wordHasUnknownKanji(String.fromCharCode(extA), const {}), isTrue);
      expect(
        wordHasUnknownKanji(String.fromCharCode(extA), const {extA}),
        isFalse,
      );
    });
  });
}
