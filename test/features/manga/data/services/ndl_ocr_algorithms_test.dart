import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/data/services/ndl_ocr_algorithms.dart';
import 'package:mekuru/features/manga/data/services/ndl_text_model.dart';

/// The same vectors as the Android NDL test, so both platforms stay in step.
final _vectors =
    jsonDecode(
          File(
            'packages/local_manga_ocr/android/src/test/resources/'
            'ndl_vectors.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

Int32List _image(int w, int h) => Int32List.fromList([
  for (var i = 0; i < w * h; i++)
    () {
      final x = i % w, y = i ~/ w;
      return (((x * 13 + y * 7) % 256) << 16) |
          (((x * 3 + y * 29) % 256) << 8) |
          ((x * 47 + y * 11) % 256);
    }(),
]);

void main() {
  group('NdlPixels', () {
    test('matches the shared digests of resized pixels and tensors', () {
      final rows = _vectors['resize'] as List;
      expect(rows, isNotEmpty);
      for (final row in rows) {
        final w = row['width'] as int, h = row['height'] as int;
        expect(NdlPixels.isVertical(w, h), row['vertical'], reason: '${w}x$h');
        final rgb = NdlPixels.resizeLine(_image(w, h), w, h);
        final bytes = Uint8List.fromList([
          for (final p in rgb) ...[(p >> 16) & 255, (p >> 8) & 255, p & 255],
        ]);
        expect(
          sha256.convert(bytes).toString(),
          row['rgbSha256'],
          reason: '${w}x$h',
        );
        final tensor = NdlPixels.normalize(rgb);
        final le = ByteData(tensor.length * 4);
        for (var i = 0; i < tensor.length; i++) {
          le.setFloat32(i * 4, tensor[i], Endian.little);
        }
        expect(
          sha256.convert(le.buffer.asUint8List()).toString(),
          row['tensorSha256'],
          reason: '${w}x$h',
        );
      }
    });
    test('a vertical line is turned counter-clockwise', () {
      // 2 wide, 3 tall: a b / c d / e f becomes b d f / a c e.
      final rotated = NdlPixels.rotateCounterClockwise(
        Int32List.fromList([1, 2, 3, 4, 5, 6]),
        2,
        3,
      );
      expect(rotated, [2, 4, 6, 1, 3, 5]);
      expect(NdlPixels.isVertical(100, 80), isFalse);
      expect(NdlPixels.isVertical(100, 81), isTrue);
    });
    test('normalization is RGB channel first, -1 to 1', () {
      expect(NdlPixels.normalize(Int32List.fromList([0xff0000, 0x00ff00])), [
        1,
        -1,
        -1,
        1,
        -1,
        -1,
      ]);
    });
    test('modelInput crops RGBA pixels before preprocessing', () {
      // 2x1 page: a red pixel then a white pixel; crop the white one.
      final page = Uint8List.fromList([255, 0, 0, 255, 255, 255, 255, 255]);
      final input = NdlPixels.modelInput(
        page,
        2,
        1,
        left: 1,
        top: 0,
        right: 2,
        bottom: 1,
      );
      expect(input.length, 3 * NdlPixels.inputWidth * NdlPixels.inputHeight);
      expect(input.every((v) => v == 1), isTrue);
    });
  });

  test('ndlDecode matches the shared cases', () {
    for (final row in _vectors['decode'] as List) {
      final logits = Float32List.fromList([
        for (final v in row['logits'] as List) (v as num).toDouble(),
      ]);
      expect(
        ndlDecode(
          logits,
          row['steps'] as int,
          row['classes'] as int,
          (row['charset'] as List).cast<String>(),
        ),
        row['text'],
      );
    }
  });

  group('parseNdlCharset', () {
    test('matches the shared cases', () {
      for (final row in _vectors['charset'] as List) {
        expect(parseNdlCharset(row['yaml'] as String), row['chars']);
      }
    });
    test('rejects a file without the charset or with other escapes', () {
      expect(() => parseNdlCharset('model:\n'), throwsFormatException);
      expect(
        () => parseNdlCharset('  charset_train: "a\\nb"\n'),
        throwsFormatException,
      );
      expect(
        () => parseNdlCharset('  charset_train: "abc\n'),
        throwsFormatException,
      );
    });
  });

  test('the model files are pinned to one NDLOCR-Lite commit', () {
    expect(ndlTextModelFiles.map((f) => f.name), [
      'parseq-ndl-24x768-100-tiny-153epoch-tegaki3-r8data-202604.onnx',
      'NDLmoji.yaml',
    ]);
    for (final f in ndlTextModelFiles) {
      expect(
        f.url,
        startsWith(
          'https://raw.githubusercontent.com/ndl-lab/ndlocr-lite/'
          '636d1cfeb1331f89f4048f416e49e23a09a714b5/src/',
        ),
      );
      expect(f.url, endsWith('/${f.name}'));
      expect(f.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
    }
    expect(ndlTextModelFiles.map((f) => f.bytes), [42588187, 42434]);
  });
}
