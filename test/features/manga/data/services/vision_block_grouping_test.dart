import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/data/services/vision_block_grouping.dart';

/// A vertical column of text, one character (40 px) wide.
VisionLine _column(
  double left,
  double top, {
  double width = 40,
  double height = 200,
  String text = 'これは',
}) => VisionLine(
  left: left,
  top: top,
  right: left + width,
  bottom: top + height,
  text: text,
);

VisionLine _row(double left, double top, {String text = 'これは'}) => VisionLine(
  left: left,
  top: top,
  right: left + 200,
  bottom: top + 40,
  text: text,
);

void main() {
  test('columns side by side form one vertical block, read right to left', () {
    final blocks = groupVisionLines([
      _column(100, 100, text: '左の行'),
      _column(200, 100, text: '右の行'),
      _column(150, 100, text: '中の行'),
    ]);

    expect(blocks, hasLength(1));
    expect(blocks.single.vertical, isTrue);
    expect(blocks.single.lines.map((l) => l.text), ['右の行', '中の行', '左の行']);
    expect(blocks.single.fontSize, 40);
  });

  test('columns a bubble apart stay separate blocks', () {
    final blocks = groupVisionLines([
      _column(100, 100),
      _column(150, 100),
      _column(400, 100),
    ]);

    expect(blocks, hasLength(2));
  });

  test('columns that do not overlap along their length are separate', () {
    final blocks = groupVisionLines([_column(100, 100), _column(150, 600)]);

    expect(blocks, hasLength(2));
  });

  test('stacked rows form one horizontal block, read top to bottom', () {
    final blocks = groupVisionLines([
      _row(100, 150, text: '下の行'),
      _row(100, 100, text: '上の行'),
    ]);

    expect(blocks, hasLength(1));
    expect(blocks.single.vertical, isFalse);
    expect(blocks.single.lines.map((l) => l.text), ['上の行', '下の行']);
  });

  test('ruby beside a column is not text, but the bounds still cover it', () {
    final blocks = groupVisionLines([
      _column(100, 100, text: '結衣が'),
      _column(142, 100, width: 18, height: 80, text: 'ゆい'),
    ]);

    expect(blocks, hasLength(1));
    expect(blocks.single.lines.map((l) => l.text), ['結衣が']);
    // The crop handed to manga-ocr reaches past the base column to the ruby.
    expect(blocks.single.right, 160);
    expect(blocks.single.left, 100);
    // Ruby is not counted when sizing the block.
    expect(blocks.single.fontSize, 40);
  });

  test('ruby between two columns of one bubble keeps them together', () {
    final blocks = groupVisionLines([
      _column(100, 100, text: '結衣が'),
      _column(142, 100, width: 18, height: 80, text: 'ゆい'),
      _column(170, 100, text: '言った'),
    ]);

    expect(blocks, hasLength(1));
    expect(blocks.single.lines.map((l) => l.text), ['言った', '結衣が']);
    expect(blocks.single.left, 100);
    expect(blocks.single.right, 210);
  });

  test('text of a very different size is a different block', () {
    final blocks = groupVisionLines([
      _column(100, 100, width: 40),
      _column(170, 100, width: 100, height: 300, text: 'えっ'),
    ]);

    expect(blocks, hasLength(2));
  });

  test('a single character joins the column beside it', () {
    final blocks = groupVisionLines([
      _column(150, 100, text: 'どうしたの'),
      _column(100, 100, height: 42, text: 'ん'),
    ]);

    expect(blocks, hasLength(1));
    expect(blocks.single.vertical, isTrue);
  });

  test('blocks come out in manga reading order', () {
    final blocks = groupVisionLines([
      _column(100, 100, text: '二番'),
      _column(800, 120, text: '一番'),
      _column(500, 900, text: '三番'),
    ]);

    expect(blocks.map((b) => b.lines.single.text), ['一番', '二番', '三番']);
  });

  test('a line found by both passes of a spread is kept once', () {
    // The same column, as the left and right pass of a spread each saw it.
    final blocks = groupVisionLines([
      _column(100, 100, text: '同じ行'),
      VisionLine(
        left: 101,
        top: 99,
        right: 141,
        bottom: 301,
        text: '同じ行',
      ),
    ]);

    expect(blocks, hasLength(1));
    expect(blocks.single.lines.map((l) => l.text), ['同じ行']);
  });

  test('two real columns side by side are not mistaken for duplicates', () {
    final blocks = groupVisionLines([
      // Boxes that overlap by a quarter of their width: close, but two lines.
      _column(100, 100, text: '右の行'),
      _column(130, 100, text: '左の行'),
    ]);

    expect(blocks.single.lines.map((l) => l.text), ['左の行', '右の行']);
  });

  test('two bubbles chained through a near line are split apart', () {
    // Two columns of one bubble, then a third column 30 px off to the side
    // and 100 px down: close enough for the gap test, so union-find chains it
    // in, but the three together leave a hole in their bounds.
    final blocks = groupVisionLines([
      _column(100, 100, text: '一行目'),
      _column(145, 100, text: '二行目'),
      _column(215, 200, text: '別の吹き出し'),
    ]);

    expect(blocks, hasLength(2));
    expect(
      blocks.map((b) => b.lines.map((l) => l.text).join()),
      containsAll(['二行目一行目', '別の吹き出し']),
    );
  });

  test('a real column that simply runs short does not split its block', () {
    final blocks = groupVisionLines([
      _column(100, 100, text: 'ながいれつ'),
      _column(145, 100, text: 'これもながい'),
      _column(190, 100, height: 60, text: 'みじかい'),
    ]);

    expect(blocks, hasLength(1));
  });

  test('blank lines are ignored', () {
    expect(groupVisionLines([_column(100, 100, text: '  ')]), isEmpty);
  });

  // Local only: the fixture is copyrighted manga and is not in the repo.
  // Make the second file with
  //   swift tools/vision_recall.swift example/mokuro/test1.mokuro --json example/mokuro/test1.vision.json
  final reference = File('example/mokuro/test1.mokuro');
  final visionLines = File('example/mokuro/test1.vision.json');
  test(
    'real pages: grouped blocks match the reference blocks',
    skip: reference.existsSync() && visionLines.existsSync()
        ? false
        : 'local fixture not present',
    () {
      final refPages = {
        for (final p
            in (jsonDecode(reference.readAsStringSync())['pages'] as List))
          p['img_path'] as String: p['blocks'] as List,
      };
      var referenceBlocks = 0;
      var matched = 0;
      var produced = 0;
      for (final page in jsonDecode(visionLines.readAsStringSync()) as List) {
        final blocks = groupVisionLines([
          for (final l in page['lines'] as List)
            VisionLine(
              left: (l['box'][0] as num).toDouble(),
              top: (l['box'][1] as num).toDouble(),
              right: (l['box'][2] as num).toDouble(),
              bottom: (l['box'][3] as num).toDouble(),
              text: l['text'] as String,
            ),
        ]);
        produced += blocks.length;
        for (final ref in refPages[page['img_path']]!) {
          referenceBlocks++;
          final box = (ref['box'] as List)
              .map((v) => (v as num).toDouble())
              .toList();
          final best = blocks.fold<double>(0, (best, b) {
            final w = math.min(b.right, box[2]) - math.max(b.left, box[0]);
            final h = math.min(b.bottom, box[3]) - math.max(b.top, box[1]);
            if (w <= 0 || h <= 0) return best;
            final union =
                (b.right - b.left) * (b.bottom - b.top) +
                (box[2] - box[0]) * (box[3] - box[1]) -
                w * h;
            return math.max(best, w * h / union);
          });
          if (best >= 0.5) matched++;
        }
      }
      // ignore: avoid_print
      print(
        'matched $matched/$referenceBlocks reference blocks (IoU >= 0.5), '
        'produced $produced blocks',
      );
      expect(matched / referenceBlocks, greaterThan(0.7));
    },
  );
}
