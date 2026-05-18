import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/reader/data/services/mecab_service.dart';

void main() {
  group('MecabFeatureLayout.ipadic', () {
    const layout = MecabFeatureLayout.ipadic;

    test('reads dictionary form from features[6]', () {
      // IPADIC noun: 食べる ← surface 食べ, conjugated form
      final features = [
        '動詞', '自立', '*', '*', '一段', '連用形', '食べる', 'タベ', 'タベ',
      ];
      expect(layout.dictionaryForm(features), '食べる');
    });

    test('reads reading from features[7]', () {
      final features = [
        '名詞', '一般', '*', '*', '*', '*', '本', 'ホン', 'ホン',
      ];
      expect(layout.reading(features), 'ホン');
    });

    test('returns null dictionaryForm for short feature arrays', () {
      // Unknown words come back from IPADIC with only the POS column.
      expect(layout.dictionaryForm(['名詞']), isNull);
    });

    test('returns empty reading for short feature arrays', () {
      expect(layout.reading(['名詞']), '');
    });

    test('treats * as missing', () {
      final features = [
        '名詞', '一般', '*', '*', '*', '*', '*', '*', '*',
      ];
      expect(layout.dictionaryForm(features), isNull);
      expect(layout.reading(features), '');
    });

    test('does not strip loanword gloss', () {
      // IPADIC entries never carry an English gloss; passthrough is fine.
      final features = [
        '名詞', '一般', '*', '*', '*', '*', 'foo-bar', 'フーバー', 'フーバー',
      ];
      expect(layout.dictionaryForm(features), 'foo-bar');
    });

    test('handles empty feature list', () {
      expect(layout.dictionaryForm(const []), isNull);
      expect(layout.reading(const []), '');
    });
  });

  group('MecabFeatureLayout.unidicLite', () {
    const layout = MecabFeatureLayout.unidicLite;

    test('reads lemma from features[7]', () {
      // 食べる ← surface 食べ in unidic-lite
      final features = [
        '動詞', '一般', '*', '*', '下一段-バ行', '連用形-一般',
        'タベル', '食べる', '食べ', 'タベ', '食べる', 'タベル',
        '和', '*', '*', '*', '*', 'タベ', 'タベル', 'タベ', 'タベル',
        '*', '*', '2', 'C1', '*',
      ];
      expect(layout.dictionaryForm(features), '食べる');
    });

    test('reads surface kana from features[17]', () {
      final features = [
        '動詞', '一般', '*', '*', '下一段-バ行', '連用形-一般',
        'タベル', '食べる', '食べ', 'タベ', '食べる', 'タベル',
        '和', '*', '*', '*', '*', 'タベ', 'タベル', 'タベ', 'タベル',
        '*', '*', '2', 'C1', '*',
      ];
      expect(layout.reading(features), 'タベ');
    });

    test('strips english gloss suffix from loanword lemma', () {
      final features = [
        '名詞', '普通名詞', '一般', '*', '*', '*',
        'コンビニ', 'コンビニ-convenience', 'コンビニ', 'コンビニ',
        'コンビニ-convenience', 'コンビニ', '外', '*', '*', '*', '*',
        'コンビニ',
      ];
      expect(layout.dictionaryForm(features), 'コンビニ');
    });

    test('returns null dictionaryForm for short feature arrays', () {
      // Unknown words in unidic-lite have only 6 fields.
      final features = ['名詞', '一般', '*', '*', '*', '*'];
      expect(layout.dictionaryForm(features), isNull);
      expect(layout.reading(features), '');
    });

    test('passes through loanword lemma when no gloss suffix is present', () {
      // Some unidic-lite katakana entries (e.g., 片仮名 ← カタカナ) have a
      // plain lemma with no `-english` suffix; nothing to strip.
      final features = [
        '名詞', '普通名詞', '一般', '*', '*', '*',
        'カタカナ', '片仮名', 'カタカナ', 'カタカナ',
        '片仮名', 'カタカナ', '和', '*', '*', '*', '*',
        'カタカナ',
      ];
      expect(layout.dictionaryForm(features), '片仮名');
    });

    test('returns null when stripped lemma would be empty', () {
      // Degenerate input: lemma starts with `-`, so strip leaves an empty
      // string. Treat as missing rather than producing a blank dict key.
      final features = [
        '名詞', '一般', '*', '*', '*', '*',
        '*', '-bogus', '*', '*', '*', '*', '*', '*', '*', '*', '*', '*',
      ];
      expect(layout.dictionaryForm(features), isNull);
    });

    test('handles empty feature list', () {
      expect(layout.dictionaryForm(const []), isNull);
      expect(layout.reading(const []), '');
    });

    test('uses surface kana without long-vowel ー', () {
      // 公園: lemma reading コウエン, surface pron コーエン, kana[17] コウエン.
      // Layout reads kana[17] so the result has no ー.
      final features = [
        '名詞', '普通名詞', '一般', '*', '*', '*',
        'コウエン', '公園', '公園', 'コーエン', '公園', 'コーエン',
        '漢', '*', '*', '*', '*', 'コウエン',
      ];
      expect(layout.reading(features), 'コウエン');
    });
  });
}
