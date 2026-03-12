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
}
