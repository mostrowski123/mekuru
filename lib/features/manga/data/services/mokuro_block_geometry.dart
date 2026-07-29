import 'dart:math' as math;
import 'dart:ui' show Rect;

import '../models/mokuro_models.dart';

/// Pure geometry for mapping character ranges in mokuro OCR text onto
/// image-pixel rectangles, using the per-line quads from the OCR data.
///
/// Block-text coordinates: `MokuroTextBlock.fullText` is `lines.join()`, so
/// cumulative line lengths convert between (lineIndex, charInLine) and an
/// offset in the block text. This file owns that convention in both
/// directions — [blockCharOffset] forward, [blockCharRangeRects] backward.

/// Convert a (lineIndex, charInLine) position to an offset in [block]'s
/// `fullText`, or `null` when the position is out of range.
int? blockCharOffset(MokuroTextBlock block, int lineIndex, int charInLine) {
  if (lineIndex < 0 || lineIndex >= block.lines.length || charInLine < 0) {
    return null;
  }

  var offset = charInLine;
  var textLength = 0;
  for (var i = 0; i < block.lines.length; i++) {
    if (i < lineIndex) offset += block.lines[i].length;
    textLength += block.lines[i].length;
  }
  return offset < textLength ? offset : null;
}

/// Compute the rectangle covering `[charStart, charEnd)` of one OCR line.
///
/// [quad] has 4 points `[topLeft, topRight, bottomRight, bottomLeft]` in
/// mokuro's image-pixel coordinate system.
///
/// For **vertical text**, characters are stacked top-to-bottom.
/// For **horizontal text**, characters flow left-to-right.
///
/// The line's extent is divided proportionally by character count.
/// [charStart]/[charEnd] are clamped into `[0, lineLength]`. Returns `null`
/// when the quad or the resulting range is unusable.
Rect? lineCharRangeRect({
  required List<List<double>> quad,
  required int lineLength,
  required int charStart,
  required int charEnd,
  required bool vertical,
}) {
  if (lineLength <= 0 || quad.length < 4) return null;
  for (var i = 0; i < 4; i++) {
    if (quad[i].length < 2) return null;
  }

  final start = charStart.clamp(0, lineLength);
  final end = charEnd.clamp(0, lineLength);
  if (end <= start) return null;

  // quad points: [topLeft, topRight, bottomRight, bottomLeft]
  final tl = quad[0]; // top-left [x, y]
  final tr = quad[1]; // top-right [x, y]
  final br = quad[2]; // bottom-right [x, y]
  final bl = quad[3]; // bottom-left [x, y]

  final startFrac = start / lineLength;
  final endFrac = end / lineLength;

  if (vertical) {
    // Vertical text: characters flow top-to-bottom.
    // Interpolate Y along the left and right edges.
    final leftTop = _lerp2(tl, bl, startFrac);
    final leftBottom = _lerp2(tl, bl, endFrac);
    final rightTop = _lerp2(tr, br, startFrac);
    final rightBottom = _lerp2(tr, br, endFrac);

    final left = math.min(leftTop.$1, rightTop.$1);
    final right = math.max(leftTop.$1, rightTop.$1);
    final top = math.min(leftTop.$2, rightTop.$2);
    final bottom = math.max(leftBottom.$2, rightBottom.$2);

    return Rect.fromLTRB(left, top, right, bottom);
  } else {
    // Horizontal text: characters flow left-to-right.
    // Interpolate X along the top and bottom edges.
    final topStart = _lerp2(tl, tr, startFrac);
    final topEnd = _lerp2(tl, tr, endFrac);
    final bottomStart = _lerp2(bl, br, startFrac);
    final bottomEnd = _lerp2(bl, br, endFrac);

    final left = math.min(topStart.$1, bottomStart.$1);
    final right = math.max(topEnd.$1, bottomEnd.$1);
    final top = math.min(topStart.$2, topEnd.$2);
    final bottom = math.max(bottomStart.$2, bottomEnd.$2);

    return Rect.fromLTRB(left, top, right, bottom);
  }
}

/// Compute the rectangles covering `[charStart, charEnd)` of [block]'s
/// `fullText`, one per line the range spans.
///
/// Indices are clamped; lines without a usable quad are skipped.
List<Rect> blockCharRangeRects(
  MokuroTextBlock block,
  int charStart,
  int charEnd,
) {
  var textLength = 0;
  for (final line in block.lines) {
    textLength += line.length;
  }
  final start = charStart.clamp(0, textLength);
  final end = charEnd.clamp(0, textLength);
  if (end <= start) return const [];

  final rects = <Rect>[];
  var lineStart = 0;
  for (var i = 0; i < block.lines.length; i++) {
    final lineLength = block.lines[i].length;
    final lineEnd = lineStart + lineLength;
    if (lineLength > 0 && lineStart < end && lineEnd > start) {
      final quad = i < block.linesCoords.length
          ? block.linesCoords[i]
          : const <List<double>>[];
      final rect = lineCharRangeRect(
        quad: quad,
        lineLength: lineLength,
        charStart: math.max(start, lineStart) - lineStart,
        charEnd: math.min(end, lineEnd) - lineStart,
        vertical: block.vertical,
      );
      if (rect != null) rects.add(rect);
    }
    if (lineEnd >= end) break;
    lineStart = lineEnd;
  }
  return rects;
}

/// Linear interpolation between two 2D points.
(double, double) _lerp2(List<double> a, List<double> b, double t) {
  return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t);
}
