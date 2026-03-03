import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mekuru/features/manga/data/services/mokuro_parser.dart';

void main() {
  group('MokuroParser.computeImageContentBoundsFromBytes', () {
    test('returns null for an all-white image', () async {
      final image = img.Image(width: 12, height: 12);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));
      final bytes = img.encodePng(image);

      final bounds = await MokuroParser.computeImageContentBoundsFromBytes(
        bytes,
      );

      expect(bounds, isNull);
    });

    test(
      'keeps a 2px buffer from the first non-white pixel on each side',
      () async {
        final image = img.Image(width: 20, height: 20);
        img.fill(image, color: img.ColorRgb8(255, 255, 255));

        for (int y = 4; y <= 14; y++) {
          for (int x = 5; x <= 11; x++) {
            image.setPixelRgb(x, y, 0, 0, 0);
          }
        }

        final bounds = await MokuroParser.computeImageContentBoundsFromBytes(
          img.encodePng(image),
        );

        expect(bounds, isNotNull);
        expect(bounds!.left, 3);
        expect(bounds.top, 2);
        expect(bounds.right, 14);
        expect(bounds.bottom, 17);
      },
    );

    test(
      'ignores isolated edge noise when cropping left and right sides',
      () async {
        final image = img.Image(width: 20, height: 20);
        img.fill(image, color: img.ColorRgb8(255, 255, 255));

        for (int y = 4; y <= 14; y++) {
          for (int x = 5; x <= 11; x++) {
            image.setPixelRgb(x, y, 0, 0, 0);
          }
        }

        image.setPixelRgb(0, 9, 0, 0, 0);
        image.setPixelRgb(19, 10, 0, 0, 0);

        final bounds = await MokuroParser.computeImageContentBoundsFromBytes(
          img.encodePng(image),
        );

        expect(bounds, isNotNull);
        expect(bounds!.left, 3);
        expect(bounds.right, 14);
      },
    );

    test(
      'keeps sparse edge content when cropping left and right sides',
      () async {
        final image = img.Image(width: 20, height: 20);
        img.fill(image, color: img.ColorRgb8(255, 255, 255));

        for (int y = 4; y <= 14; y++) {
          for (int x = 6; x <= 11; x++) {
            image.setPixelRgb(x, y, 0, 0, 0);
          }
        }

        for (final y in [4, 6, 8, 10, 12]) {
          image.setPixelRgb(5, y, 0, 0, 0);
        }
        for (final y in [5, 7, 9, 11, 13]) {
          image.setPixelRgb(12, y, 0, 0, 0);
        }

        final bounds = await MokuroParser.computeImageContentBoundsFromBytes(
          img.encodePng(image),
        );

        expect(bounds, isNotNull);
        expect(bounds!.left, 3);
        expect(bounds.right, 15);
      },
    );

    test(
      'custom white threshold can ignore near-white compression artifacts',
      () async {
        final image = img.Image(width: 20, height: 20);
        img.fill(image, color: img.ColorRgb8(255, 255, 255));

        for (int y = 4; y <= 14; y++) {
          image.setPixelRgb(0, y, 235, 235, 235);
          image.setPixelRgb(19, y, 235, 235, 235);
          for (int x = 5; x <= 11; x++) {
            image.setPixelRgb(x, y, 0, 0, 0);
          }
        }

        final bounds = await MokuroParser.computeImageContentBoundsFromBytes(
          img.encodePng(image),
          whiteThreshold: 230,
        );

        expect(bounds, isNotNull);
        expect(bounds!.left, 3);
        expect(bounds.right, 14);
      },
    );
  });
}
