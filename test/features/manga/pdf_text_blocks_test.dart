import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/data/services/pdf_text_blocks.dart';

const _size = 20.0;

/// A column of [text] drawn top to bottom from ([x], [top]), one em per
/// glyph, as a vertical book's PDF draws it.
List<PdfGlyph> _column(
  double x,
  double top,
  String text, {
  double size = _size,
}) => [
  for (final (i, char) in text.split('').indexed)
    PdfGlyph(char, x, top + i * size, x + size, top + (i + 1) * size),
];

/// A row of [text] drawn left to right from ([left], [y]).
List<PdfGlyph> _row(
  double left,
  double y,
  String text, {
  double size = _size,
}) => [
  for (final (i, char) in text.split('').indexed)
    PdfGlyph(char, left + i * size, y, left + (i + 1) * size, y + size),
];

void main() {
  test('a vertical page reads columns right to left, glyphs top down', () {
    // Columns two ems apart, glyphs aligned across them as on a real grid.
    final blocks = pdfPageBlocks([
      ..._column(300, 100, 'きょうはがっこうで'),
      ..._column(260, 100, 'にほんごをべんきょう'),
      ..._column(220, 100, 'します。'),
    ]);

    expect(blocks.first.vertical, isTrue);
    expect(blocks, hasLength(1));
    final block = blocks.single;
    expect(block.vertical, isTrue);
    expect(block.lines, ['きょうはがっこうで', 'にほんごをべんきょう', 'します。']);
    expect(block.box, [220, 100, 320, 300]);
    expect(block.linesCoords.first, [
      [300, 100],
      [320, 100],
      [320, 280],
      [300, 280],
    ]);
    expect(block.fontSize, _size);
  });

  test('a horizontal page reads rows top down, glyphs left to right', () {
    final blocks = pdfPageBlocks([
      ..._row(40, 100, 'きょうはがっこうで'),
      ..._row(40, 130, 'にほんごをべんきょう'),
    ]);

    expect(blocks.first.vertical, isFalse);
    expect(blocks.single.lines, ['きょうはがっこうで', 'にほんごをべんきょう']);
    expect(blocks.single.vertical, isFalse);
  });

  test('drops furigana, which is drawn at about half size', () {
    final blocks = pdfPageBlocks([
      ..._column(300, 100, '学校に行く'),
      ..._column(320, 100, 'がっこう', size: 10),
    ]);

    expect(blocks.single.lines, ['学校に行く']);
  });

  test('keeps small kana and punctuation, which PDFium boxes by ink', () {
    // Ink boxes: ょ and っ sit low and right in their cell, 。 top right
    // (vertical) or low left (horizontal); furigana sits beside the line.
    PdfGlyph small(String char, double left, double top) =>
        PdfGlyph(char, left, top, left + 9, top + 9);
    final vertical = pdfPageBlocks([
      ..._column(300, 100, 'ち'),
      small('ょ', 309, 129),
      small('っ', 309, 149),
      ..._column(300, 160, 'とまって'),
      small('。', 309, 241),
      small('ま', 322, 165), // reading beside the column
    ]);
    final horizontal = pdfPageBlocks([
      ..._row(100, 300, 'ち'),
      small('ょ', 122, 309),
      small('っ', 142, 309),
      ..._row(160, 300, 'とまって'),
      small('。', 242, 310),
      small('ま', 165, 288), // reading above the row
    ]);

    expect(vertical.single.lines, ['ちょっとまって。']);
    expect(horizontal.first.vertical, isFalse);
    expect(horizontal.single.lines, ['ちょっとまって。']);
  });

  test('distant paragraphs become separate blocks', () {
    final blocks = pdfPageBlocks([
      ..._column(300, 100, 'はじめのだんらく'),
      ..._column(260, 100, 'のつづき'),
      ..._column(100, 100, 'つぎのだんらく'),
    ]);

    expect(blocks.map((b) => b.lines).toList(), [
      ['はじめのだんらく', 'のつづき'],
      ['つぎのだんらく'],
    ]);
  });

  test('phrase spaces keep a column one line (graded readers use them)', () {
    final blocks = pdfPageBlocks([
      ..._column(300, 100, 'きょうは'),
      // A one-em space between phrases.
      ..._column(300, 100 + 5 * _size, 'がっこうで'),
      ..._column(260, 100, 'べんきょう'),
    ]);

    expect(blocks.single.lines, ['きょうはがっこうで', 'べんきょう']);
  });

  test('a wide gap inside a column starts a new line', () {
    final blocks = pdfPageBlocks([
      ..._column(300, 40, 'みだし'),
      ..._column(300, 300, 'ほんぶん'),
    ]);

    expect(blocks.expand((b) => b.lines).toList(), ['みだし', 'ほんぶん']);
  });

  test('ignores whitespace and characters that cannot be text', () {
    final blocks = pdfPageBlocks([
      ..._column(300, 100, 'ねこがすき'),
      const PdfGlyph(' ', 300, 200, 320, 220),
      const PdfGlyph('\u{E000}', 300, 220, 320, 240),
      const PdfGlyph('\u{FFFD}', 300, 240, 320, 260),
      const PdfGlyph('\u{3000}', 300, 260, 320, 280),
    ]);

    expect(blocks.single.lines, ['ねこがすき']);
  });

  test('a text layer of junk characters counts as no text', () {
    // Fonts mapped to the wrong characters: accented Latin, rare CJK.
    expect(pdfPageBlocks(_row(20, 20, 'äĝĀťıĻķĒÞèäÿ')), isEmpty);
    expect(pdfPageBlocks(_column(300, 20, '䛣䜜䛿䚷䛔䛱䛤䛾')), isEmpty);
    // Glyph ids mapped to ASCII punctuation, with a few real kanji.
    expect(pdfPageBlocks(_row(20, 20, '日本!"##\$%正月\$%&(()*+')), isEmpty);
  });

  test('English around Japanese examples keeps the Japanese', () {
    final blocks = pdfPageBlocks([
      ..._row(20, 20, 'The word for school is'),
      ..._row(20, 60, '学校（がっこう）。'),
    ]);

    expect(blocks, isNotEmpty);
    expect(blocks.map((b) => b.lines.join()).join(), contains('学校（がっこう）'));
  });

  test('a page without text has no blocks', () {
    expect(pdfPageBlocks(const []), isEmpty);
    expect(pdfPageBlocks(const [PdfGlyph(' ', 0, 0, 10, 10)]), isEmpty);
  });
}
