import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/data/services/manga_ocr_algorithms.dart';

/// The same vectors as the Android `OcrAlgorithmsTest`, so both platforms
/// stay in step.
void main() {
  group('alignLines', () {
    test('unchanged lines retain their boundaries', () {
      expect(alignLines('今日は晴れです', ['今日は', '晴れです']), ['今日は', '晴れです']);
    });
    test('a correction inside a line preserves the boundaries', () {
      expect(alignLines('今日は晴れです', ['令日は', '晴れです']), ['今日は', '晴れです']);
    });
    test('an insertion at the boundary is ambiguous', () {
      expect(alignLines('abcdXefgh', ['abcd', 'efgh']), isNull);
    });
    test('repeated characters do not invent a boundary', () {
      expect(alignLines('あああああ', ['ああ', 'ああ']), isNull);
    });
    test('disagreement above the threshold falls back', () {
      expect(alignLines('月曜日です', ['火星', '大好き']), isNull);
    });
    test('empty anchors and text fall back', () {
      expect(alignLines('abc', ['', 'abc']), isNull);
      expect(alignLines('', ['abc', 'def']), isNull);
      expect(alignLines('abc', []), isNull);
    });
    test('supplementary kanji are not split', () {
      expect(alignLines('𠮷野家です', ['𠮷野家', 'です']), ['𠮷野家', 'です']);
    });
  });

  group('MangaOcrDecode', () {
    test('a greedy step never repeats a trigram', () {
      // Sequence 2,5,6,5,6: choosing 5 again would repeat the trigram 5,6,5.
      const logits = [0.0, 0.0, 0.0, 0.0, 0.0, 9.0, 1.0, 8.0];
      expect(MangaOcrDecode.next(logits, [2, 5, 6, 5, 6]), 7);
      expect(MangaOcrDecode.next(logits, [2, 5, 6]), 5);
    });
    test('argmax ties use the first id', () {
      expect(MangaOcrDecode.next([1, 1], []), 0);
    });
    test('postProcess matches manga_ocr', () {
      expect(MangaOcrDecode.postProcess('こん にち\nは'), 'こんにちは');
      // Vectors checked against manga_ocr.ocr.post_process 0.1.16.
      expect(MangaOcrDecode.postProcess('え…'), 'え．．．');
      expect(MangaOcrDecode.postProcess('あ・・・・'), 'あ．．．．');
      expect(MangaOcrDecode.postProcess('ABC123!?'), 'ＡＢＣ１２３！？');
      expect(MangaOcrDecode.postProcess('x-y_z~'), 'ｘ－ｙ＿ｚ～');
      expect(MangaOcrDecode.postProcess('ｶﾞｷﾞﾊﾟ｡ｰ'), 'ガギパ。ー');
      expect(MangaOcrDecode.postProcess('ｦﾞ'), 'ヲﾞ');
      expect(MangaOcrDecode.postProcess('ﾞ'), 'ﾞ');
      expect(MangaOcrDecode.postProcess('漢字ひらがな'), '漢字ひらがな');
    });
  });

  group('OcrPixels', () {
    test('grayscale matches Pillow luma', () {
      Int32List one(int p) => Int32List.fromList([p]);
      expect(OcrPixels.grayscale(one(0xff0000))[0], 0x4c4c4c);
      expect(OcrPixels.grayscale(one(0xffffff))[0], 0xffffff);
      expect(OcrPixels.grayscale(one(0x000000))[0], 0x000000);
    });
    test('resize preserves a constant colour up and down', () {
      for (final (w, h) in [(1, 1), (17, 31), (640, 310)]) {
        final source = Int32List(w * h)..fillRange(0, w * h, 0x1234ab);
        expect(
          OcrPixels.resizeRgb(source, w, h).every((p) => p == 0x1234ab),
          isTrue,
        );
      }
    });
    test('normalization is RGB channel first', () {
      final result = OcrPixels.normalize(
        Int32List.fromList([0xff0000, 0x00ff00]),
        .5,
        .5,
      );
      expect(result.sublist(0, 4), [1, -1, -1, 1]);
    });
    test('preprocessing matches the independent Pillow golden digests', () {
      final rows =
          jsonDecode(
                File(
                  'packages/local_manga_ocr/android/src/test/resources/'
                  'pillow_bicubic_vectors.json',
                ).readAsStringSync(),
              )
              as List;
      expect(rows, isNotEmpty);
      for (final row in rows) {
        final w = row['width'] as int;
        final h = row['height'] as int;
        final source = Int32List.fromList([
          for (var i = 0; i < w * h; i++)
            () {
              final x = i % w, y = i ~/ w;
              return (((x * 13 + y * 7) % 256) << 16) |
                  (((x * 3 + y * 29) % 256) << 8) |
                  ((x * 47 + y * 11) % 256);
            }(),
        ]);
        final rgb = OcrPixels.resizeRgb(source, w, h);
        final bytes = Uint8List.fromList([
          for (final p in rgb) ...[(p >> 16) & 255, (p >> 8) & 255, p & 255],
        ]);
        expect(
          sha256.convert(bytes).toString(),
          row['sha256'],
          reason: '${w}x$h',
        );
      }
    });
    test('modelInput crops RGBA pixels before preprocessing', () {
      // 2x1 page: a red pixel then a white pixel; crop the white one.
      final page = Uint8List.fromList([255, 0, 0, 255, 255, 255, 255, 255]);
      final input = OcrPixels.modelInput(
        page,
        2,
        1,
        left: 1,
        top: 0,
        right: 2,
        bottom: 1,
      );
      expect(input.length, 3 * 224 * 224);
      expect(input.every((v) => v == 1), isTrue);
    });
  });
}
