/// Pre- and post-processing for NDLOCR-Lite's text-line recognizer (PARSeq,
/// the 100-character model, National Diet Library, CC BY 4.0), which reads
/// the long lines of scanned text pages that manga-ocr cannot.
///
/// Mirrors `src/parseq.py` of ndl-lab/ndlocr-lite: a line crop is turned
/// upright, resized to 768x24 like `cv2.resize(INTER_LINEAR)`, scaled to
/// [-1, 1] channel first, and the model's output is decoded greedily up to
/// the first end token. Android's Kotlin mirror checks the same vectors
/// (`ndl_vectors.json`), so both platforms feed the model identical tensors.
/// Pure logic, no Flutter imports.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'manga_ocr_algorithms.dart';

/// The `charset_train` list of NDLOCR-Lite's `NDLmoji.yaml`, the one
/// `ocr.py` gives the recognizer: that line's double-quoted value, with `\"`
/// and `\\` unescaped (the only escapes it uses), split into code points.
List<String> parseNdlCharset(String yaml) {
  const key = 'charset_train:';
  final line = yaml
      .split('\n')
      .firstWhere(
        (l) => l.trimLeft().startsWith(key),
        orElse: () => throw const FormatException('No charset_train'),
      );
  final quote = line.indexOf('"', line.indexOf(key));
  if (quote < 0) throw const FormatException('charset_train is not quoted');
  final chars = <String>[];
  var escaped = false;
  for (final rune in line.substring(quote + 1).runes) {
    final ch = String.fromCharCode(rune);
    if (escaped) {
      if (ch != '"' && ch != r'\') {
        throw FormatException('Unsupported escape \\$ch in charset_train');
      }
      chars.add(ch);
      escaped = false;
    } else if (ch == r'\') {
      escaped = true;
    } else if (ch == '"') {
      return chars;
    } else {
      chars.add(ch);
    }
  }
  throw const FormatException('charset_train is not terminated');
}

/// Greedy decoding of the recognizer's `[1, steps, classes]` [logits]: the
/// best class at each step (the first on ties, like `numpy.argmax`) up to the
/// first end token, class 0. Class `i` is `charset[i - 1]`.
String ndlDecode(
  Float32List logits,
  int steps,
  int classes,
  List<String> charset,
) {
  final text = StringBuffer();
  for (var step = 0; step < steps; step++) {
    final row = step * classes;
    var best = 0;
    for (var c = 1; c < classes; c++) {
      if (logits[row + c] > logits[row + best]) best = c;
    }
    if (best == 0) break;
    text.write(charset[best - 1]);
  }
  return text.toString();
}

/// The recognizer's input image. Pixels are packed 0xRRGGBB.
abstract final class NdlPixels {
  static const inputWidth = 768;
  static const inputHeight = 24;

  /// NDL reads a line as vertical, and turns it upright, when it is taller
  /// than 0.8 times its width.
  static bool isVertical(int width, int height) => height > width * 0.8;

  /// `cv2.ROTATE_90_COUNTERCLOCKWISE`: the result is [height] wide and
  /// [width] tall, and its top row is the input's rightmost column.
  static Int32List rotateCounterClockwise(
    Int32List pixels,
    int width,
    int height,
  ) {
    final out = Int32List(pixels.length);
    for (var y = 0; y < width; y++) {
      for (var x = 0; x < height; x++) {
        out[y * height + x] = pixels[x * width + width - 1 - y];
      }
    }
    return out;
  }

  /// `cv2.resize(INTER_LINEAR)` semantics: half-pixel centres, no
  /// antialiasing, edges clamped. OpenCV interpolates in 11-bit fixed point,
  /// so it can differ from this by one per channel.
  ///
  /// Computed in doubles in exactly this order, so that a port with IEEE
  /// doubles (and no fused multiply-add) gets bit-identical pixels:
  /// - per axis, `scale = input / output`, `at = (i + 0.5) * scale - 0.5`
  ///   clamped to `[0, input - 1]`, `i0 = floor(at)`,
  ///   `i1 = min(i0 + 1, input - 1)`, `w1 = at - i0`, `w0 = 1 - w1`;
  /// - per channel, `top = p(x0, y0) * wx0 + p(x1, y0) * wx1`, `bottom`
  ///   the same on row y1, `v = top * wy0 + bottom * wy1`, and the result is
  ///   `floor(v + 0.5)`.
  static Int32List resize(
    Int32List pixels,
    int width,
    int height, {
    int outWidth = inputWidth,
    int outHeight = inputHeight,
  }) {
    assert(width > 0 && height > 0 && pixels.length == width * height);
    final xs = _taps(width, outWidth);
    final ys = _taps(height, outHeight);
    final out = Int32List(outWidth * outHeight);
    for (var y = 0; y < outHeight; y++) {
      final (y0, y1, wy0, wy1) = ys[y];
      for (var x = 0; x < outWidth; x++) {
        final (x0, x1, wx0, wx1) = xs[x];
        final p00 = pixels[y0 * width + x0], p01 = pixels[y0 * width + x1];
        final p10 = pixels[y1 * width + x0], p11 = pixels[y1 * width + x1];
        var rgb = 0;
        for (var shift = 16; shift >= 0; shift -= 8) {
          final top =
              ((p00 >> shift) & 255) * wx0 + ((p01 >> shift) & 255) * wx1;
          final bottom =
              ((p10 >> shift) & 255) * wx0 + ((p11 >> shift) & 255) * wx1;
          rgb = (rgb << 8) | (top * wy0 + bottom * wy1 + .5).floor();
        }
        out[y * outWidth + x] = rgb;
      }
    }
    return out;
  }

  static List<(int, int, double, double)> _taps(int input, int output) {
    final scale = input / output;
    return [
      for (var i = 0; i < output; i++)
        () {
          final at = math.min(
            math.max((i + .5) * scale - .5, 0.0),
            input - 1.0,
          );
          final i0 = at.floor();
          final w1 = at - i0;
          return (i0, math.min(i0 + 1, input - 1), 1 - w1, w1);
        }(),
    ];
  }

  /// One line crop, upright and resized to [inputWidth] x [inputHeight].
  static Int32List resizeLine(Int32List pixels, int width, int height) =>
      isVertical(width, height)
      ? resize(rotateCounterClockwise(pixels, width, height), height, width)
      : resize(pixels, width, height);

  /// Channel-first float tensor of `v / 127.5 - 1`, rounded to float32 after
  /// the division and again after the subtraction, as numpy computes NDL's
  /// (`v / 127.5f - 1f` in float arithmetic).
  static Float32List normalize(Int32List rgb) {
    final out = Float32List(rgb.length * 3);
    for (var i = 0; i < out.length; i++) {
      final c = i ~/ rgb.length;
      out[i] = _scaled[(rgb[i % rgb.length] >> (16 - c * 8)) & 255];
    }
    return out;
  }

  static final _scaled = () {
    final table = Float32List(256);
    for (var v = 0; v < 256; v++) {
      table[v] = v / 127.5;
      // Exact in doubles, so storing rounds once, like float32 subtraction.
      table[v] -= 1;
    }
    return table;
  }();

  /// The model input `[1, 3, 24, 768]` for one line of a page: crop [left],
  /// [top]..[right],[bottom] out of tightly packed RGBA [page] pixels (as
  /// [OcrPixels.modelInput] does), then [resizeLine] and [normalize]. NDL
  /// crops a line's box with no padding.
  static Float32List modelInput(
    Uint8List page,
    int pageWidth,
    int pageHeight, {
    required int left,
    required int top,
    required int right,
    required int bottom,
  }) {
    final crop = OcrPixels.crop(
      page,
      pageWidth,
      pageHeight,
      left: left,
      top: top,
      right: right,
      bottom: bottom,
    );
    return normalize(resizeLine(crop.pixels, crop.width, crop.height));
  }
}
