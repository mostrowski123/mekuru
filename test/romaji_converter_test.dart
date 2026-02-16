import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/dictionary/data/services/romaji_converter.dart';

void main() {
  group('RomajiConverter.isRomaji', () {
    test('returns true for ASCII letters', () {
      expect(RomajiConverter.isRomaji('hello'), isTrue);
      expect(RomajiConverter.isRomaji('kokuritsu'), isTrue);
      expect(RomajiConverter.isRomaji('A'), isTrue);
    });

    test('returns false for non-ASCII', () {
      expect(RomajiConverter.isRomaji('こんにちは'), isFalse);
      expect(RomajiConverter.isRomaji('国立'), isFalse);
      expect(RomajiConverter.isRomaji('hello123'), isFalse);
      expect(RomajiConverter.isRomaji(''), isFalse);
    });

    test('returns false for mixed ASCII and numbers', () {
      expect(RomajiConverter.isRomaji('abc123'), isFalse);
      expect(RomajiConverter.isRomaji('test!'), isFalse);
    });
  });

  group('RomajiConverter.convert', () {
    test('converts basic vowels', () {
      expect(RomajiConverter.convert('a'), 'あ');
      expect(RomajiConverter.convert('i'), 'い');
      expect(RomajiConverter.convert('u'), 'う');
      expect(RomajiConverter.convert('e'), 'え');
      expect(RomajiConverter.convert('o'), 'お');
    });

    test('converts basic syllables', () {
      expect(RomajiConverter.convert('ka'), 'か');
      expect(RomajiConverter.convert('ki'), 'き');
      expect(RomajiConverter.convert('ku'), 'く');
      expect(RomajiConverter.convert('ke'), 'け');
      expect(RomajiConverter.convert('ko'), 'こ');
    });

    test('converts multi-syllable words', () {
      expect(RomajiConverter.convert('sakura'), 'さくら');
      expect(RomajiConverter.convert('tokyo'), 'ときょ');
      expect(RomajiConverter.convert('nihon'), 'にほん');
      expect(RomajiConverter.convert('sushi'), 'すし');
    });

    test('converts kokuritsu correctly', () {
      expect(RomajiConverter.convert('kokuritsu'), 'こくりつ');
    });

    test('converts words with n before consonant', () {
      expect(RomajiConverter.convert('sanpo'), 'さんぽ');
      expect(RomajiConverter.convert('sensei'), 'せんせい');
      expect(RomajiConverter.convert('shinbun'), 'しんぶん');
    });

    test('converts n at end of string', () {
      expect(RomajiConverter.convert('san'), 'さん');
      expect(RomajiConverter.convert('hon'), 'ほん');
      expect(RomajiConverter.convert('nin'), 'にん');
    });

    test('converts nn to ん', () {
      expect(RomajiConverter.convert('onna'), 'おんな');
      expect(RomajiConverter.convert('konnichi'), 'こんにち');
    });

    test('converts double consonants to っ', () {
      expect(RomajiConverter.convert('kitte'), 'きって');
      expect(RomajiConverter.convert('motto'), 'もっと');
      expect(RomajiConverter.convert('gakkou'), 'がっこう');
      expect(RomajiConverter.convert('zasshi'), 'ざっし');
    });

    test('converts palatalized sounds', () {
      expect(RomajiConverter.convert('kya'), 'きゃ');
      expect(RomajiConverter.convert('kyu'), 'きゅ');
      expect(RomajiConverter.convert('kyo'), 'きょ');
      expect(RomajiConverter.convert('sha'), 'しゃ');
      expect(RomajiConverter.convert('shu'), 'しゅ');
      expect(RomajiConverter.convert('sho'), 'しょ');
      expect(RomajiConverter.convert('cha'), 'ちゃ');
      expect(RomajiConverter.convert('chu'), 'ちゅ');
      expect(RomajiConverter.convert('cho'), 'ちょ');
    });

    test('converts special syllables', () {
      expect(RomajiConverter.convert('shi'), 'し');
      expect(RomajiConverter.convert('chi'), 'ち');
      expect(RomajiConverter.convert('tsu'), 'つ');
      expect(RomajiConverter.convert('fu'), 'ふ');
    });

    test('converts ga/za/da/ba/pa rows', () {
      expect(RomajiConverter.convert('ga'), 'が');
      expect(RomajiConverter.convert('za'), 'ざ');
      expect(RomajiConverter.convert('da'), 'だ');
      expect(RomajiConverter.convert('ba'), 'ば');
      expect(RomajiConverter.convert('pa'), 'ぱ');
    });

    test('handles case insensitivity', () {
      expect(RomajiConverter.convert('TOKYO'), 'ときょ');
      expect(RomajiConverter.convert('Sakura'), 'さくら');
    });

    test('handles partial/incomplete input by stripping trailing', () {
      // 'kok' → 'こ' (k is incomplete syllable, stripped)
      expect(RomajiConverter.convert('kok'), 'こ');
      // 'kokur' → 'こく' (r is incomplete)
      expect(RomajiConverter.convert('kokur'), 'こく');
    });

    test('handles empty input', () {
      expect(RomajiConverter.convert(''), '');
    });

    test('converts common words correctly', () {
      expect(RomajiConverter.convert('taberu'), 'たべる');
      expect(RomajiConverter.convert('nomu'), 'のむ');
      expect(RomajiConverter.convert('hashiru'), 'はしる');
      expect(RomajiConverter.convert('aruku'), 'あるく');
    });
  });

  group('RomajiConverter.katakanaToHiragana', () {
    test('converts basic katakana', () {
      expect(RomajiConverter.katakanaToHiragana('カタカナ'), 'かたかな');
      expect(RomajiConverter.katakanaToHiragana('トウキョウ'), 'とうきょう');
    });

    test('preserves hiragana', () {
      expect(RomajiConverter.katakanaToHiragana('ひらがな'), 'ひらがな');
    });

    test('handles mixed input', () {
      expect(RomajiConverter.katakanaToHiragana('カタかな'), 'かたかな');
    });

    test('preserves kanji and other characters', () {
      expect(RomajiConverter.katakanaToHiragana('東京タワー'), '東京たわー');
    });

    test('preserves prolonged sound mark', () {
      expect(RomajiConverter.katakanaToHiragana('ラーメン'), 'らーめん');
    });
  });
}
