import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';

void main() {
  group('MokuroBook ocrCompleted', () {
    test('toJson writes explicit ocrCompleted flag', () {
      const book = MokuroBook(
        title: 'Test',
        imageDirPath: '/images',
        ocrSource: 'custom_ocr',
        ocrCompleted: true,
        pages: [],
      );

      final json = book.toJson();

      expect(json['ocrCompleted'], isTrue);
    });

    test('fromJson infers true for legacy mokuro cache', () {
      final book = MokuroBook.fromJson({
        'title': 'Imported HTML',
        'imageDirPath': '/images',
        'ocrSource': 'mokuro',
        'pages': [],
      });

      expect(book.ocrCompleted, isTrue);
    });

    test('fromJson infers true for legacy custom OCR cache', () {
      final book = MokuroBook.fromJson({
        'title': 'Custom OCR',
        'imageDirPath': '/images',
        'ocrSource': 'custom_ocr',
        'pages': [],
      });

      expect(book.ocrCompleted, isTrue);
    });

    test('fromJson infers false for legacy cache without OCR source', () {
      final book = MokuroBook.fromJson({
        'title': 'Pending OCR',
        'imageDirPath': '/images',
        'pages': [],
      });

      expect(book.ocrCompleted, isFalse);
    });
  });

  group('MokuroTextBlock.fromOcrJson', () {
    Map<String, dynamic> validBlockJson() => {
      'box': [10, 20, 110, 220],
      'vertical': true,
      'font_size': 24.5,
      'lines_coords': [
        [
          [10, 20],
          [110, 20],
          [110, 220],
          [10, 220],
        ],
      ],
      'lines': ['こんにちは'],
    };

    test('parses a fully populated block', () {
      final block = MokuroTextBlock.fromOcrJson(validBlockJson());

      expect(block.box, [10.0, 20.0, 110.0, 220.0]);
      expect(block.vertical, isTrue);
      expect(block.fontSize, 24.5);
      expect(block.linesCoords, hasLength(1));
      expect(block.linesCoords.first, hasLength(4));
      expect(block.lines, ['こんにちは']);
    });

    test('tolerates null lines_coords (MEKURU-12 regression)', () {
      final json = validBlockJson()..['lines_coords'] = null;

      final block = MokuroTextBlock.fromOcrJson(json);

      expect(block.linesCoords, isEmpty);
      expect(block.lines, ['こんにちは']);
    });

    test('tolerates missing lines_coords key', () {
      final json = validBlockJson()..remove('lines_coords');

      final block = MokuroTextBlock.fromOcrJson(json);

      expect(block.linesCoords, isEmpty);
    });

    test('applies defaults for missing box, vertical, font_size and lines', () {
      final block = MokuroTextBlock.fromOcrJson(<String, dynamic>{});

      expect(block.box, [0.0, 0.0, 0.0, 0.0]);
      expect(block.vertical, isTrue);
      expect(block.fontSize, 0.0);
      expect(block.linesCoords, isEmpty);
      expect(block.lines, isEmpty);
    });

    test('keeps lines_coords index-aligned when one quad is malformed', () {
      final json = validBlockJson()
        ..['lines'] = ['一行目', '二行目', '三行目']
        ..['lines_coords'] = [
          [
            [10, 20],
            [30, 20],
            [30, 200],
            [10, 200],
          ],
          null,
          [
            [50, 20],
            [70, 20],
            [70, 200],
            [50, 200],
          ],
        ];

      final block = MokuroTextBlock.fromOcrJson(json);

      expect(block.linesCoords, hasLength(3));
      expect(block.linesCoords[0], hasLength(4));
      expect(block.linesCoords[1], isEmpty);
      expect(block.linesCoords[2], hasLength(4));
      expect(block.linesCoords[2].first, [50.0, 20.0]);
    });

    test('replaces quads containing malformed points with empty quads', () {
      final json = validBlockJson()
        ..['lines_coords'] = [
          [
            [10, null],
            [30, 20],
            [30, 200],
            [10, 200],
          ],
        ];

      final block = MokuroTextBlock.fromOcrJson(json);

      expect(block.linesCoords, hasLength(1));
      expect(block.linesCoords.first, isEmpty);
    });

    test('replaces null line entries with empty strings to keep alignment', () {
      final json = validBlockJson()..['lines'] = ['一行目', null, '三行目'];

      final block = MokuroTextBlock.fromOcrJson(json);

      expect(block.lines, ['一行目', '', '三行目']);
    });

    test('coerces integer font_size and box values to doubles', () {
      final json = validBlockJson()
        ..['font_size'] = 24
        ..['box'] = [1, 2, 3, 4];

      final block = MokuroTextBlock.fromOcrJson(json);

      expect(block.fontSize, 24.0);
      expect(block.box, [1.0, 2.0, 3.0, 4.0]);
    });
  });
}
