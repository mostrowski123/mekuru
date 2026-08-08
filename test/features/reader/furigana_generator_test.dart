import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/reader/data/services/furigana_generator.dart';
import 'package:mekuru/features/reader/data/services/mecab_service.dart';

class _FakeTokenizer implements FuriganaTokenizer {
  _FakeTokenizer(this._byInput, {this.ready = true});
  final Map<String, List<TokenInfo>> _byInput;
  final bool ready;

  @override
  Future<bool> ensureReady() async => ready;

  @override
  List<TokenInfo> tokenize(String text) =>
      _byInput[text] ?? const <TokenInfo>[];
}

TokenInfo _tok(String surface, String reading, int start) => TokenInfo(
  surface: surface,
  dictionaryForm: surface,
  reading: reading,
  pos: '',
  startInText: start,
);

Future<Map<String, Object?>> _generateOne(
  Map<String, List<TokenInfo>> tokensByInput,
  String input,
) async {
  final generator = FuriganaGenerator(_FakeTokenizer(tokensByInput));
  return (await generator.generate([input]))!.first;
}

void main() {
  group('FuriganaGenerator', () {
    test('returns null when the tokenizer is unavailable', () async {
      // An uninitialized MeCab must surface as "unavailable" (null), never as
      // plain unannotated segments — the JS bridge caches those permanently.
      final generator = FuriganaGenerator(
        _FakeTokenizer(const {}, ready: false),
      );
      expect(await generator.generate(['食べた']), isNull);
    });

    test('emits a single bare segment when input has no tokens', () async {
      final result = await _generateOne({}, 'hello');
      expect(result, {
        'source': 'hello',
        'segments': [
          {'t': 'hello'},
        ],
      });
    });

    test('aligns kanji+kana within a single token', () async {
      // 食べた → token surface "食べた", reading "タベタ"
      final result = await _generateOne({
        '食べた': [_tok('食べた', 'タベタ', 0)],
      }, '食べた');
      expect(result['source'], '食べた');
      expect(result['segments'], [
        {'t': '食', 'f': 'た'},
        {'t': 'べた'},
      ]);
    });

    test('multiple tokens with mixed kanji/kana', () async {
      // 今日は晴れだ
      // tokens (fake): 今日(キョウ)@0, は()@2, 晴れ(ハレ)@3, だ()@5
      final result = await _generateOne({
        '今日は晴れだ': [
          _tok('今日', 'キョウ', 0),
          _tok('は', '', 2),
          _tok('晴れ', 'ハレ', 3),
          _tok('だ', '', 5),
        ],
      }, '今日は晴れだ');
      expect(result['segments'], [
        {'t': '今日', 'f': 'きょう'},
        {'t': 'は'},
        {'t': '晴', 'f': 'は'},
        {'t': 'れ'},
        {'t': 'だ'},
      ]);
    });

    test('token without a reading is emitted as bare text', () async {
      final result = await _generateOne({
        'abc': [_tok('abc', '', 0)],
      }, 'abc');
      expect(result['segments'], [
        {'t': 'abc'},
      ]);
    });

    test('gaps between tokens are filled with bare text', () async {
      final result = await _generateOne({
        'a食b': [_tok('食', 'ショク', 1)],
      }, 'a食b');
      expect(result['segments'], [
        {'t': 'a'},
        {'t': '食', 'f': 'しょく'},
        {'t': 'b'},
      ]);
    });

    test('generate processes batched inputs in order', () async {
      final generator = FuriganaGenerator(
        _FakeTokenizer({
          '行く': [_tok('行く', 'イク', 0)],
          'なし': const <TokenInfo>[],
        }),
      );
      final result = (await generator.generate(['行く', 'なし']))!;
      expect(result.length, 2);
      expect(result[0]['source'], '行く');
      expect((result[0]['segments'] as List).first, {'t': '行', 'f': 'い'});
      expect(result[1]['source'], 'なし');
      expect((result[1]['segments'] as List).first, {'t': 'なし'});
    });

    test('skipToken emits skipped tokens as bare text', () async {
      final generator = FuriganaGenerator(
        _FakeTokenizer({
          '憂鬱な日': [
            _tok('憂鬱', 'ユウウツ', 0),
            _tok('な', '', 2),
            _tok('日', 'ヒ', 3),
          ],
        }),
        skipToken: (t) => t.surface == '日',
      );
      final result = (await generator.generate(['憂鬱な日']))!.first;
      expect(result['segments'], [
        {'t': '憂鬱', 'f': 'ゆううつ'},
        {'t': 'な'},
        {'t': '日'},
      ]);
    });

    test('empty input produces empty segments', () async {
      final result = await _generateOne({}, '');
      expect(result, {
        'source': '',
        'segments': const <Map<String, Object?>>[],
      });
    });
  });
}
