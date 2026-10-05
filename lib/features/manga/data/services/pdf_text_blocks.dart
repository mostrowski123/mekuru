// Pure Dart: lays a PDF page's text layer out as manga-reader text blocks,
// so words in imported PDFs are tappable without OCR.
import 'dart:math' as math;

import 'package:mekuru/core/utils/japanese_text.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';

/// One character the PDF draws, boxed in the rendered page image's pixels.
class PdfGlyph {
  const PdfGlyph(this.char, this.left, this.top, this.right, this.bottom);

  final String char;
  final double left;
  final double top;
  final double right;
  final double bottom;

  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;

  /// Glyph size: a CJK glyph is about square; half-width ones are narrow,
  /// so the longer side is the font size either way.
  double get size => math.max(right - left, bottom - top);
}

/// Furigana is drawn at about half the base size. Glyphs under this share
/// of the page's median size are small; beside the lines they are readings,
/// not text to look up. PDFium boxes glyphs by their ink, so small kana and
/// punctuation are small too, but they sit inside a line.
const _rubyRatio = 0.6;

/// A page has text when it carries at least [_minJapanese] Japanese
/// characters and they make up [_minJapaneseShare] of everything but plain
/// Latin letters (so English textbooks with Japanese examples keep theirs).
/// Some PDFs map their font to the wrong characters, and their "text" is
/// junk: accented Latin, phonetic letters, rare CJK in place of kana.
/// tools/build_tadoku_catalog.py applies the same rule.
const _minJapanese = 5;
const _minJapaneseShare = 0.6;

/// Lays out [glyphs], given in the PDF's drawing order, into blocks of
/// lines in reading order: columns right to left for vertical text, rows
/// top to bottom for horizontal. A page has one direction, so every block
/// shares it; a page without text has no blocks.
///
/// Readings, whitespace and characters that cannot be text (private-use,
/// replacement, control) are dropped first, and a page whose text is not
/// Japanese has none ([_minJapanese]). Japanese text sits on a grid, so
/// geometry alone cannot tell columns from rows; the drawing order can —
/// one glyph after another steps along the line.
List<MokuroTextBlock> pdfPageBlocks(List<PdfGlyph> glyphs) {
  final text = glyphs.where((g) => _isText(g.char)).toList();
  if (!_isJapaneseText(text)) return const [];
  final median = _median([for (final g in text) g.size]);
  final base = <PdfGlyph>[];
  final small = <PdfGlyph>[];
  for (final glyph in text) {
    (glyph.size >= median * _rubyRatio ? base : small).add(glyph);
  }
  final vertical = _drawnVertically(base, median);
  final lines = _lines(base, median, vertical: vertical);
  _addSmallGlyphs(lines, small, median, vertical: vertical);
  return [
    for (final block in _blocks(lines, median, vertical: vertical))
      _toMokuro(block, median, vertical: vertical),
  ];
}

bool _isText(String char) {
  if (char.trim().isEmpty) return false; // includes U+3000
  final code = char.runes.first;
  if (code < 0x20 || (code >= 0x7F && code < 0xA0)) return false;
  if (code >= 0xE000 && code <= 0xF8FF) return false; // private use
  return code != 0xFFFD;
}

bool _isJapaneseText(List<PdfGlyph> text) {
  var japanese = 0;
  var counted = 0;
  for (final glyph in text) {
    final code = glyph.char.runes.first;
    if ((code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A)) {
      continue; // plain Latin letters: English around Japanese examples
    }
    counted++;
    if (isJapaneseTextChar(code)) japanese++;
  }
  return japanese >= _minJapanese && japanese >= counted * _minJapaneseShare;
}

double _median(List<double> values) {
  final sorted = [...values]..sort();
  return sorted[sorted.length ~/ 2];
}

/// Whether consecutive glyphs mostly step down (vertical text) rather than
/// across. Steps longer than two glyphs are jumps to another line, not the
/// next character, and do not vote. Ties count as vertical, the norm for
/// Japanese books.
bool _drawnVertically(List<PdfGlyph> glyphs, double size) {
  var down = 0;
  var across = 0;
  for (var i = 1; i < glyphs.length; i++) {
    final dx = (glyphs[i].centerX - glyphs[i - 1].centerX).abs();
    final dy = (glyphs[i].centerY - glyphs[i - 1].centerY).abs();
    if (dx > size * 2 || dy > size * 2) continue;
    dy > dx ? down++ : across++;
  }
  return down >= across;
}

/// Cuts the glyphs, in drawing order, into lines: a glyph continues the line
/// when it steps on along it — down a column, right along a row — within the
/// line's width and at most a couple of ems on (graded readers space their
/// phrases apart). Anything else is a new line.
List<List<PdfGlyph>> _lines(
  List<PdfGlyph> glyphs,
  double size, {
  required bool vertical,
}) {
  final lines = <List<PdfGlyph>>[];
  for (final glyph in glyphs) {
    final previous = lines.lastOrNull?.last;
    final continues =
        previous != null &&
        (vertical
            ? (glyph.centerX - previous.centerX).abs() <= size * 0.5 &&
                  glyph.top >= previous.top &&
                  glyph.top - previous.bottom <= size * 2.5
            : (glyph.centerY - previous.centerY).abs() <= size * 0.5 &&
                  glyph.left >= previous.left &&
                  glyph.left - previous.right <= size * 2.5);
    if (continues) {
      lines.last.add(glyph);
    } else {
      lines.add([glyph]);
    }
  }
  return lines;
}

/// Puts each small glyph whose centre is within a line — across it, and at
/// most an em past its ends — into that line at its place. The rest sit
/// beside the lines: furigana, dropped.
void _addSmallGlyphs(
  List<List<PdfGlyph>> lines,
  List<PdfGlyph> small,
  double size, {
  required bool vertical,
}) {
  final boxes = [for (final line in lines) _box(line)];
  final grown = <int>{};
  for (final glyph in small) {
    for (var i = 0; i < lines.length; i++) {
      final (l, t, r, b) = boxes[i];
      final (x, y) = (glyph.centerX, glyph.centerY);
      final inside = vertical
          ? x >= l && x <= r && y >= t - size && y <= b + size
          : y >= t && y <= b && x >= l - size && x <= r + size;
      if (inside) {
        lines[i].add(glyph);
        grown.add(i);
        break;
      }
    }
  }
  for (final i in grown) {
    lines[i].sort(
      (a, b) => vertical
          ? a.centerY.compareTo(b.centerY)
          : a.centerX.compareTo(b.centerX),
    );
  }
}

/// Box of [glyphs]: left, top, right, bottom.
(double, double, double, double) _box(Iterable<PdfGlyph> glyphs) => (
  glyphs.map((g) => g.left).reduce(math.min),
  glyphs.map((g) => g.top).reduce(math.min),
  glyphs.map((g) => g.right).reduce(math.max),
  glyphs.map((g) => g.bottom).reduce(math.max),
);

/// Groups consecutive lines that read on from one another — the next column
/// to the left (vertical) or the next row down (horizontal), close by and
/// overlapping along the line — into blocks. Drawing order is reading
/// order, so a line that does not follow on starts a new block.
List<List<List<PdfGlyph>>> _blocks(
  List<List<PdfGlyph>> lines,
  double size, {
  required bool vertical,
}) {
  final blocks = <List<List<PdfGlyph>>>[];
  for (final line in lines) {
    final previous = blocks.lastOrNull?.last;
    var follows = false;
    if (previous != null) {
      final (l, t, r, b) = _box(line);
      final (pl, pt, pr, pb) = _box(previous);
      final gap = vertical ? pl - r : t - pb;
      final overlap = vertical
          ? math.min(b, pb) - math.max(t, pt)
          : math.min(r, pr) - math.max(l, pl);
      follows = gap >= -size * 0.5 && gap <= size * 1.5 && overlap > 0;
    }
    if (follows) {
      blocks.last.add(line);
    } else {
      blocks.add([line]);
    }
  }
  return blocks;
}

MokuroTextBlock _toMokuro(
  List<List<PdfGlyph>> lines,
  double size, {
  required bool vertical,
}) {
  final (l, t, r, b) = _box(lines.expand((line) => line));
  return MokuroTextBlock(
    box: [l, t, r, b],
    vertical: vertical,
    fontSize: size,
    linesCoords: [
      for (final line in lines)
        if (_box(line) case (final ll, final lt, final lr, final lb))
          [
            [ll, lt],
            [lr, lt],
            [lr, lb],
            [ll, lb],
          ],
    ],
    lines: [for (final line in lines) line.map((g) => g.char).join()],
  );
}
