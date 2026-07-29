import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/data/services/mokuro_block_geometry.dart';

// 400px wide, 100px tall line — 4 chars of horizontal text.
const _horizontalQuad = [
  [0.0, 0.0],
  [400.0, 0.0],
  [400.0, 100.0],
  [0.0, 100.0],
];

// 100px wide, 400px tall line — 4 chars of vertical text.
const _verticalQuad = [
  [0.0, 0.0],
  [100.0, 0.0],
  [100.0, 400.0],
  [0.0, 400.0],
];

MokuroTextBlock _block({
  required List<String> lines,
  List<List<List<double>>>? linesCoords,
  bool vertical = false,
}) {
  return MokuroTextBlock(
    box: const [0, 0, 400, 100],
    vertical: vertical,
    fontSize: 24,
    linesCoords:
        linesCoords ?? List.generate(lines.length, (_) => _horizontalQuad),
    lines: lines,
  );
}

void main() {
  group('blockCharOffset', () {
    test('sums earlier line lengths', () {
      final block = _block(lines: ['あいう', 'えお']);
      expect(blockCharOffset(block, 0, 0), 0);
      expect(blockCharOffset(block, 0, 2), 2);
      expect(blockCharOffset(block, 1, 0), 3);
      expect(blockCharOffset(block, 1, 1), 4);
    });

    test('rejects out-of-range positions', () {
      final block = _block(lines: ['あいう', 'えお']);
      expect(blockCharOffset(block, -1, 0), isNull);
      expect(blockCharOffset(block, 2, 0), isNull);
      expect(blockCharOffset(block, 0, -1), isNull);
      expect(blockCharOffset(block, 1, 2), isNull, reason: 'past end of text');
      expect(blockCharOffset(_block(lines: []), 0, 0), isNull);
    });
  });

  group('lineCharRangeRect', () {
    test('horizontal range at line start', () {
      final rect = lineCharRangeRect(
        quad: _horizontalQuad,
        lineLength: 4,
        charStart: 0,
        charEnd: 2,
        vertical: false,
      );
      expect(rect, const Rect.fromLTRB(0, 0, 200, 100));
    });

    test('horizontal range mid-line', () {
      final rect = lineCharRangeRect(
        quad: _horizontalQuad,
        lineLength: 4,
        charStart: 1,
        charEnd: 3,
        vertical: false,
      );
      expect(rect, const Rect.fromLTRB(100, 0, 300, 100));
    });

    test('vertical range interpolates along the vertical axis', () {
      final rect = lineCharRangeRect(
        quad: _verticalQuad,
        lineLength: 4,
        charStart: 1,
        charEnd: 3,
        vertical: true,
      );
      expect(rect, const Rect.fromLTRB(0, 100, 100, 300));
    });

    test('clamps out-of-range indices to the line', () {
      final rect = lineCharRangeRect(
        quad: _horizontalQuad,
        lineLength: 4,
        charStart: -5,
        charEnd: 99,
        vertical: false,
      );
      expect(rect, const Rect.fromLTRB(0, 0, 400, 100));
    });

    test('returns null for degenerate input', () {
      Rect? call({
        List<List<double>> quad = _horizontalQuad,
        int lineLength = 4,
        int charStart = 0,
        int charEnd = 2,
      }) {
        return lineCharRangeRect(
          quad: quad,
          lineLength: lineLength,
          charStart: charStart,
          charEnd: charEnd,
          vertical: false,
        );
      }

      expect(call(quad: const []), isNull);
      expect(
        call(
          quad: const [
            [0.0, 0.0],
            [400.0],
            [400.0, 100.0],
            [0.0, 100.0],
          ],
        ),
        isNull,
        reason: 'quad point with fewer than 2 coords must not throw',
      );
      expect(call(lineLength: 0), isNull);
      expect(call(charStart: 2, charEnd: 2), isNull);
      expect(call(charStart: 3, charEnd: 1), isNull);
    });
  });

  group('blockCharRangeRects', () {
    test('single-line block, full range covers the line quad', () {
      final block = _block(lines: ['あいうえ']);
      final rects = blockCharRangeRects(block, 0, 4);
      expect(rects, [const Rect.fromLTRB(0, 0, 400, 100)]);
    });

    test('range crossing a line break yields one rect per line', () {
      final block = _block(lines: ['あいう', 'えお']);
      final rects = blockCharRangeRects(block, 2, 4);
      expect(rects, hasLength(2));
      // chars [2, 3) of line 0 (3 chars long)
      expect(
        rects[0],
        rectMoreOrLessEquals(const Rect.fromLTRB(400 * 2 / 3, 0, 400, 100)),
      );
      // chars [0, 1) of line 1 (2 chars long)
      expect(rects[1], const Rect.fromLTRB(0, 0, 200, 100));
    });

    test('clamps range into the block text', () {
      final block = _block(lines: ['あいうえ']);
      expect(
        blockCharRangeRects(block, -5, 999),
        blockCharRangeRects(block, 0, 4),
      );
      expect(blockCharRangeRects(block, 2, 2), isEmpty);
      expect(blockCharRangeRects(block, 10, 12), isEmpty);
    });

    test('lines without a usable quad contribute nothing', () {
      final block = _block(
        lines: ['あい', 'うえ'],
        linesCoords: [
          const [], // malformed quad — parser emits an empty list
          _horizontalQuad,
        ],
      );
      final rects = blockCharRangeRects(block, 0, 4);
      expect(rects, [const Rect.fromLTRB(0, 0, 400, 100)]);
    });

    test('linesCoords shorter than lines skips uncovered lines', () {
      final block = _block(lines: ['あい', 'うえ'], linesCoords: [_horizontalQuad]);
      final rects = blockCharRangeRects(block, 0, 4);
      expect(rects, [const Rect.fromLTRB(0, 0, 400, 100)]);
    });

    test('empty line strings keep offsets aligned', () {
      final block = _block(
        lines: ['あ', '', 'い'],
        linesCoords: [_horizontalQuad, const [], _horizontalQuad],
      );
      // Range [1, 2) is entirely within line 2.
      final rects = blockCharRangeRects(block, 1, 2);
      expect(rects, [const Rect.fromLTRB(0, 0, 400, 100)]);
    });

    test('empty block yields no rects', () {
      final block = _block(lines: [], linesCoords: []);
      expect(blockCharRangeRects(block, 0, 1), isEmpty);
    });
  });
}
