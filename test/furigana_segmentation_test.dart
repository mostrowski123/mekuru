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

    test('reading equals expression returns single segment without furigana',
        () {
      final segments = segmentFurigana('たべる', 'たべる');
      expect(segments, hasLength(1));
      expect(segments[0].text, 'たべる');
      expect(segments[0].furigana, isNull);
    });

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
