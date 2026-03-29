import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/shared/widgets/furigana_text.dart';

void main() {
  group('segmentFurigana', () {
    test('kanji + trailing kana: only kanji gets furigana', () {
      final segments = segmentFurigana('行く', 'いく');
      expect(segments, hasLength(2));
      // 行 → い
      expect(segments[0].text, '行');
      expect(segments[0].furigana, 'い');
      // く → no furigana
      expect(segments[1].text, 'く');
      expect(segments[1].furigana, isNull);
    });

    test('kanji + middle kana: reading splits correctly', () {
      final segments = segmentFurigana('食べる', 'たべる');
      expect(segments, hasLength(2));
      // 食 → た
      expect(segments[0].text, '食');
      expect(segments[0].furigana, 'た');
      // べる → no furigana
      expect(segments[1].text, 'べる');
      expect(segments[1].furigana, isNull);
    });

    test('all-kanji expression: full reading as furigana', () {
      final segments = segmentFurigana('血液', 'けつえき');
      expect(segments, hasLength(1));
      expect(segments[0].text, '血液');
      expect(segments[0].furigana, 'けつえき');
    });

    test('leading kana + kanji + trailing kana', () {
      final segments = segmentFurigana('お金持ち', 'おかねもち');
      expect(segments, hasLength(3));
      // お → no furigana
      expect(segments[0].text, 'お');
      expect(segments[0].furigana, isNull);
      // 金持 → かねも
      expect(segments[1].text, '金持');
      expect(segments[1].furigana, 'かねも');
      // ち → no furigana
      expect(segments[2].text, 'ち');
      expect(segments[2].furigana, isNull);
    });

    test('multiple kanji groups separated by kana', () {
      // 東京に行く → とうきょうにいく
      final segments = segmentFurigana('東京に行く', 'とうきょうにいく');
      expect(segments, hasLength(4));
      // 東京 → とうきょう
      expect(segments[0].text, '東京');
      expect(segments[0].furigana, 'とうきょう');
      // に → no furigana
      expect(segments[1].text, 'に');
      expect(segments[1].furigana, isNull);
      // 行 → い
      expect(segments[2].text, '行');
      expect(segments[2].furigana, 'い');
      // く → no furigana
      expect(segments[3].text, 'く');
      expect(segments[3].furigana, isNull);
    });

    test(
      'repeated kana boundary still assigns furigana to both kanji runs',
      () {
        final segments = segmentFurigana('聞き手', 'ききて');
        expect(segments, hasLength(3));
        expect(segments[0].text, '聞');
        expect(segments[0].furigana, 'き');
        expect(segments[1].text, 'き');
        expect(segments[1].furigana, isNull);
        expect(segments[2].text, '手');
        expect(segments[2].furigana, 'て');
      },
    );

    test(
      'repeated kana boundary across multiple kanji groups aligns each group',
      () {
        final segments = segmentFurigana('聞き取り手', 'ききとりて');
        expect(segments, hasLength(5));
        expect(segments[0].text, '聞');
        expect(segments[0].furigana, 'き');
        expect(segments[1].text, 'き');
        expect(segments[1].furigana, isNull);
        expect(segments[2].text, '取');
        expect(segments[2].furigana, 'と');
        expect(segments[3].text, 'り');
        expect(segments[3].furigana, isNull);
        expect(segments[4].text, '手');
        expect(segments[4].furigana, 'て');
      },
    );

    test('mixed hiragana and katakana okurigana align correctly', () {
      final segments = segmentFurigana('消しゴム', 'けしごむ');
      expect(segments, hasLength(2));
      expect(segments[0].text, '消');
      expect(segments[0].furigana, 'け');
      expect(segments[1].text, 'しゴム');
      expect(segments[1].furigana, isNull);
    });

    test('small tsu between kanji groups is treated as kana', () {
      final segments = segmentFurigana('突っ込む', 'つっこむ');
      expect(segments, hasLength(4));
      expect(segments[0].text, '突');
      expect(segments[0].furigana, 'つ');
      expect(segments[1].text, 'っ');
      expect(segments[1].furigana, isNull);
      expect(segments[2].text, '込');
      expect(segments[2].furigana, 'こ');
      expect(segments[3].text, 'む');
      expect(segments[3].furigana, isNull);
    });

    test('kanji iteration mark is grouped with the kanji run', () {
      final segments = segmentFurigana('時々', 'ときどき');
      expect(segments, hasLength(1));
      expect(segments[0].text, '時々');
      expect(segments[0].furigana, 'ときどき');
    });

    test('kanji-like abbreviation mark is grouped with the kanji run', () {
      final segments = segmentFurigana('一ヶ月', 'いっかげつ');
      expect(segments, hasLength(1));
      expect(segments[0].text, '一ヶ月');
      expect(segments[0].furigana, 'いっかげつ');
    });

    test('kanji-like symbol at the start of a word is supported', () {
      final segments = segmentFurigana('〆切', 'しめきり');
      expect(segments, hasLength(1));
      expect(segments[0].text, '〆切');
      expect(segments[0].furigana, 'しめきり');
    });

    test('katakana reading is converted to hiragana for alignment', () {
      // Reading in katakana (as MeCab returns)
      final segments = segmentFurigana('食べる', 'タベル');
      expect(segments, hasLength(2));
      expect(segments[0].text, '食');
      // Furigana should be in hiragana
      expect(segments[0].furigana, 'た');
      expect(segments[1].text, 'べる');
      expect(segments[1].furigana, isNull);
    });

    test('empty reading returns single segment without furigana', () {
      final segments = segmentFurigana('食べる', '');
      expect(segments, hasLength(1));
      expect(segments[0].text, '食べる');
      expect(segments[0].furigana, isNull);
    });

    test(
      'reading equals expression returns single segment without furigana',
      () {
        final segments = segmentFurigana('たべる', 'たべる');
        expect(segments, hasLength(1));
        expect(segments[0].text, 'たべる');
        expect(segments[0].furigana, isNull);
      },
    );

    test('all-kana expression returns single segment without furigana', () {
      final segments = segmentFurigana('おはよう', 'おはよう');
      expect(segments, hasLength(1));
      expect(segments[0].text, 'おはよう');
      expect(segments[0].furigana, isNull);
    });

    test('single kanji expression', () {
      final segments = segmentFurigana('私', 'わたし');
      expect(segments, hasLength(1));
      expect(segments[0].text, '私');
      expect(segments[0].furigana, 'わたし');
    });

    test('行う produces correct segments', () {
      final segments = segmentFurigana('行う', 'おこなう');
      expect(segments, hasLength(2));
      expect(segments[0].text, '行');
      expect(segments[0].furigana, 'おこな');
      expect(segments[1].text, 'う');
      expect(segments[1].furigana, isNull);
    });

    test('大きい (i-adjective)', () {
      final segments = segmentFurigana('大きい', 'おおきい');
      expect(segments, hasLength(2));
      expect(segments[0].text, '大');
      expect(segments[0].furigana, 'おお');
      expect(segments[1].text, 'きい');
      expect(segments[1].furigana, isNull);
    });

    test('落ち着く (multiple kanji groups)', () {
      final segments = segmentFurigana('落ち着く', 'おちつく');
      expect(segments, hasLength(4));
      expect(segments[0].text, '落');
      expect(segments[0].furigana, 'お');
      expect(segments[1].text, 'ち');
      expect(segments[1].furigana, isNull);
      expect(segments[2].text, '着');
      expect(segments[2].furigana, 'つ');
      expect(segments[3].text, 'く');
      expect(segments[3].furigana, isNull);
    });

    test('mismatched reading falls back to full furigana', () {
      // Completely mismatched reading that can't be aligned
      final segments = segmentFurigana('食べる', 'xyz');
      expect(segments, hasLength(1));
      expect(segments[0].text, '食べる');
      expect(segments[0].furigana, 'xyz');
    });
  });
}
