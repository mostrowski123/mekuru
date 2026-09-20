/// manga-ocr's pre- and post-processing for iOS, where the model runs through
/// ONNX Runtime behind a thin native channel and everything else happens here.
///
/// A port of Mekuru's own Android code (`OcrAlgorithms.kt` in
/// `packages/local_manga_ocr`), checked against the same vectors, so both
/// platforms feed the model identical pixels and clean its text identically.
/// Pure logic, no Flutter imports.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// Greedy decoding and text clean-up matching manga_ocr's generation config
/// and `post_process()`.
abstract final class MangaOcrDecode {
  static const bos = 2;
  static const eos = 3;
  static const maxTokens = 300;
  static const _noRepeatNgram = 3;

  /// Argmax over [logits], never completing a trigram already in [sequence].
  static int next(List<double> logits, List<int> sequence) {
    final banned = <int>{};
    const prefix = _noRepeatNgram - 1;
    if (sequence.length >= prefix) {
      final a = sequence[sequence.length - 2];
      final b = sequence[sequence.length - 1];
      for (var i = 0; i + _noRepeatNgram <= sequence.length; i++) {
        if (sequence[i] == a && sequence[i + 1] == b) {
          banned.add(sequence[i + prefix]);
        }
      }
    }
    var best = -1;
    for (var i = 0; i < logits.length; i++) {
      if (!banned.contains(i) && (best < 0 || logits[i] > logits[best])) {
        best = i;
      }
    }
    return best;
  }

  static const _halfKana =
      '｡｢｣､･ｦｧｨｩｪｫｬｭｮｯｰｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ';
  static const _fullKana =
      '。「」、・ヲァィゥェォャュョッーアイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワン';

  /// Precomposed voiced and semi-voiced kana, as jaconv composes them.
  static const _voiced = {
    'ウ': 'ヴ', 'カ': 'ガ', 'キ': 'ギ', 'ク': 'グ', 'ケ': 'ゲ', 'コ': 'ゴ', //
    'サ': 'ザ', 'シ': 'ジ', 'ス': 'ズ', 'セ': 'ゼ', 'ソ': 'ゾ', 'タ': 'ダ',
    'チ': 'ヂ', 'ツ': 'ヅ', 'テ': 'デ', 'ト': 'ド', 'ハ': 'バ', 'ヒ': 'ビ',
    'フ': 'ブ', 'ヘ': 'ベ', 'ホ': 'ボ',
  };
  static const _semiVoiced = {
    'ハ': 'パ', 'ヒ': 'ピ', 'フ': 'プ', 'ヘ': 'ペ', 'ホ': 'ポ', //
  };

  /// `manga_ocr.ocr.post_process`: strip whitespace, normalize dot runs, then
  /// `jaconv.h2z(ascii=True, digit=True)` with its default kana conversion.
  static String postProcess(String text) {
    var result = text.replaceAll(RegExp(r'\s'), '').replaceAll('…', '...');
    result = result.replaceAllMapped(
      RegExp('[・.]{2,}'),
      (m) => '.' * m[0]!.length,
    );
    final out = <String>[];
    for (final rune in result.runes) {
      final ch = String.fromCharCode(rune);
      final kana = _halfKana.indexOf(ch);
      if (kana >= 0) {
        out.add(_fullKana[kana]);
      } else if (ch == 'ﾞ' || ch == 'ﾟ') {
        // jaconv composes only where a precomposed kana exists (ｶﾞ -> ガ)
        // and otherwise keeps the half-width mark as is.
        final composed = out.isEmpty
            ? null
            : (ch == 'ﾞ' ? _voiced : _semiVoiced)[out.last];
        composed == null ? out.add(ch) : out[out.length - 1] = composed;
      } else if (rune >= 0x21 && rune <= 0x7e) {
        out.add(String.fromCharCode(rune + 0xFEE0));
      } else {
        out.add(ch);
      }
    }
    return out.join();
  }
}

/// Splits the reading of a whole block ([whole]) back into its lines, using
/// the per-line readings ([lines]) only as anchors. The whole-block reading
/// has more context and is usually better; null means the boundaries are
/// ambiguous and the caller should keep the per-line readings.
///
/// Offsets are Unicode code points, never splitting a surrogate pair.
List<String>? alignLines(String whole, List<String> lines) {
  if (lines.isEmpty || lines.any((l) => l.isEmpty) || whole.isEmpty) {
    return null;
  }
  if (lines.length == 1) return [whole];
  final source = lines.join().runes.toList();
  final target = whole.runes.toList();
  final n = source.length;
  final m = target.length;
  // Decoding is bounded, but also bound independently for malformed inputs.
  if (n * m > 4000000) return null;

  final forward = List.generate(n + 1, (_) => Int32List(m + 1));
  for (var i = 0; i <= n; i++) {
    forward[i][0] = i;
  }
  for (var j = 0; j <= m; j++) {
    forward[0][j] = j;
  }
  for (var i = 1; i <= n; i++) {
    for (var j = 1; j <= m; j++) {
      forward[i][j] = math.min(
        math.min(forward[i - 1][j] + 1, forward[i][j - 1] + 1),
        forward[i - 1][j - 1] + (source[i - 1] == target[j - 1] ? 0 : 1),
      );
    }
  }
  final cost = forward[n][m];
  if (cost / math.max(n, m) > .25) return null;

  final backward = List.generate(n + 1, (_) => Int32List(m + 1));
  for (var i = 0; i <= n; i++) {
    backward[i][m] = n - i;
  }
  for (var j = 0; j <= m; j++) {
    backward[n][j] = m - j;
  }
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      backward[i][j] = math.min(
        math.min(backward[i + 1][j] + 1, backward[i][j + 1] + 1),
        backward[i + 1][j + 1] + (source[i] == target[j] ? 0 : 1),
      );
    }
  }

  final cuts = [0];
  var boundary = 0;
  for (final line in lines.take(lines.length - 1)) {
    boundary += line.runes.length;
    final candidates = [
      for (var j = 0; j <= m; j++)
        if (forward[boundary][j] + backward[boundary][j] == cost) j,
    ];
    if (candidates.length != 1 || candidates.single <= cuts.last) return null;
    cuts.add(candidates.single);
  }
  if (cuts.last >= m) return null;
  cuts.add(m);
  return [
    for (var i = 0; i + 1 < cuts.length; i++)
      String.fromCharCodes(target.sublist(cuts[i], cuts[i + 1])),
  ];
}

/// Pillow-compatible pixel preparation: grayscale, then a separable bicubic
/// resize with antialiasing on downscaling and rounding after each pass.
/// Pixels are packed 0xRRGGBB.
abstract final class OcrPixels {
  /// PIL `convert("L")` replicated into every channel.
  static Int32List grayscale(Int32List rgb) {
    final out = Int32List(rgb.length);
    for (var i = 0; i < rgb.length; i++) {
      final p = rgb[i];
      final l =
          (((p >> 16) & 255) * 19595 +
              ((p >> 8) & 255) * 38470 +
              (p & 255) * 7471 +
              0x8000) >>
          16;
      out[i] = (l << 16) | (l << 8) | l;
    }
    return out;
  }

  static double _kernel(double x0) {
    final x = x0.abs();
    if (x < 1) return ((1.5 * x - 2.5) * x) * x + 1;
    if (x < 2) return (((-.5 * x + 2.5) * x - 4) * x) + 2;
    return 0;
  }

  static List<({int first, Int32List weights})> _coefficients(
    int input,
    int output,
  ) {
    final scale = input / output;
    final filterScale = math.max(1.0, scale);
    return [
      for (var at = 0; at < output; at++)
        () {
          final center = (at + .5) * scale;
          final first = math.max(0, (center - 2 * filterScale + .5).toInt());
          final end = math.min(input, (center + 2 * filterScale + .5).toInt());
          final raw = [
            for (var k = 0; k < end - first; k++)
              _kernel((k + first - center + .5) / filterScale),
          ];
          final sum = raw.fold<double>(0, (a, b) => a + b);
          return (
            first: first,
            weights: Int32List.fromList([
              for (final r in raw)
                () {
                  final value = r / sum * (1 << 22);
                  return value < 0
                      ? (value - .5).toInt()
                      : (value + .5).toInt();
                }(),
            ]),
          );
        }(),
    ];
  }

  static int _channel(int sum) => (sum >> 22).clamp(0, 255);

  static Int32List resizeRgb(
    Int32List pixels,
    int width,
    int height, {
    int size = 224,
  }) {
    assert(width > 0 && height > 0 && pixels.length == width * height);
    final xs = _coefficients(width, size);
    final ys = _coefficients(height, size);
    final middle = Int32List(size * height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < size; x++) {
        final c = xs[x];
        var r = 1 << 21, g = 1 << 21, b = 1 << 21;
        for (var k = 0; k < c.weights.length; k++) {
          final p = pixels[y * width + c.first + k];
          final w = c.weights[k];
          r += ((p >> 16) & 255) * w;
          g += ((p >> 8) & 255) * w;
          b += (p & 255) * w;
        }
        middle[y * size + x] =
            (_channel(r) << 16) | (_channel(g) << 8) | _channel(b);
      }
    }
    final out = Int32List(size * size);
    for (var index = 0; index < out.length; index++) {
      final x = index % size;
      final c = ys[index ~/ size];
      var r = 1 << 21, g = 1 << 21, b = 1 << 21;
      for (var k = 0; k < c.weights.length; k++) {
        final p = middle[(c.first + k) * size + x];
        final w = c.weights[k];
        r += ((p >> 16) & 255) * w;
        g += ((p >> 8) & 255) * w;
        b += (p & 255) * w;
      }
      out[index] = (_channel(r) << 16) | (_channel(g) << 8) | _channel(b);
    }
    return out;
  }

  /// Channel-first float tensor, `(x/255 - mean) / std` per channel.
  static Float32List normalize(Int32List rgb, double mean, double std) {
    final out = Float32List(rgb.length * 3);
    for (var i = 0; i < out.length; i++) {
      final c = i ~/ rgb.length;
      final value = (rgb[i % rgb.length] >> (16 - c * 8)) & 255;
      out[i] = (value / 255 - mean) / std;
    }
    return out;
  }

  /// The model input for one region of a page: crop [left],[top]..[right],
  /// [bottom] out of tightly packed RGBA [page] pixels, then manga-ocr's
  /// preprocessing (grayscale, 224x224 bicubic, mean and std of 0.5).
  static Float32List modelInput(
    Uint8List page,
    int pageWidth,
    int pageHeight, {
    required int left,
    required int top,
    required int right,
    required int bottom,
  }) {
    final x0 = left.clamp(0, pageWidth - 1);
    final y0 = top.clamp(0, pageHeight - 1);
    final x1 = right.clamp(x0 + 1, pageWidth);
    final y1 = bottom.clamp(y0 + 1, pageHeight);
    final w = x1 - x0;
    final h = y1 - y0;
    final crop = Int32List(w * h);
    for (var y = 0; y < h; y++) {
      var at = ((y0 + y) * pageWidth + x0) * 4;
      for (var x = 0; x < w; x++, at += 4) {
        crop[y * w + x] = (page[at] << 16) | (page[at + 1] << 8) | page[at + 2];
      }
    }
    return normalize(resizeRgb(grayscale(crop), w, h), .5, .5);
  }
}
