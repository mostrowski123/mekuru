import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mekuru/features/manga/data/services/mokuro_parser.dart';

/// Fills a content block with a staggered pattern that avoids triggering
/// the multi-phase algorithm's border-line detection (Phase 2.75/3.75).
///
/// Pixels are set to black except where `(x + y) % 9 == 0`, creating
/// ~88.9% density per column/row — below the 90% border-line threshold,
/// while maintaining consecutive dark runs of 8 (meeting the minRunLength
/// requirement for column and row content detection).
void _fillStaggeredContent(
  img.Image image, {
  required int left,
  required int top,
  required int right,
  required int bottom,
  int r = 0,
  int g = 0,
  int b = 0,
}) {
  for (int y = top; y <= bottom; y++) {
    for (int x = left; x <= right; x++) {
      if ((x + y) % 9 != 0) {
        image.setPixelRgb(x, y, r, g, b);
      }
    }
  }
}

/// Creates a 200×200 white image with a staggered content block
/// at x=[40,150], y=[30,170].
img.Image _createBaseTestImage() {
  final image = img.Image(width: 200, height: 200);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  _fillStaggeredContent(image, left: 40, top: 30, right: 150, bottom: 170);
  return image;
}

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
        // 200×200 image with content at x=[40,150], y=[30,170].
        // The staggered pattern avoids triggering border-line detection
        // while remaining realistic enough for all algorithm phases.
        final image = _createBaseTestImage();

        final bounds = await MokuroParser.computeImageContentBoundsFromBytes(
          img.encodePng(image),
        );

        expect(bounds, isNotNull);
        // Content left=40, padding=2 → 38
        expect(bounds!.left, 38);
        // Content top=30, padding=2 → 28
        expect(bounds.top, 28);
        // Content right=150 (inclusive) + 1 + padding=2 → 153
        expect(bounds.right, 153);
        // Content bottom=170 (inclusive) + 1 + padding=2 → 173
        expect(bounds.bottom, 173);
      },
    );

    test(
      'ignores isolated edge noise when cropping left and right sides',
      () async {
        final image = _createBaseTestImage();

        // Single dark pixels at the extreme edges — run of 1 is far below
        // the minRunLength=8 threshold, so they should be ignored.
        image.setPixelRgb(0, 100, 0, 0, 0);
        image.setPixelRgb(199, 100, 0, 0, 0);

        final bounds = await MokuroParser.computeImageContentBoundsFromBytes(
          img.encodePng(image),
        );

        expect(bounds, isNotNull);
        // Left/right should match main content, ignoring edge noise.
        expect(bounds!.left, 38);
        expect(bounds.right, 153);
      },
    );

    test(
      'custom white threshold can ignore near-white compression artifacts',
      () async {
        final image = _createBaseTestImage();

        // Add gray (235) columns at the image edges spanning the content
        // height. At the default threshold (240), these would be "content"
        // but at threshold 230 they should be treated as white.
        for (int y = 30; y <= 170; y++) {
          image.setPixelRgb(0, y, 235, 235, 235);
          image.setPixelRgb(199, y, 235, 235, 235);
        }

        final bounds = await MokuroParser.computeImageContentBoundsFromBytes(
          img.encodePng(image),
          whiteThreshold: 230,
        );

        expect(bounds, isNotNull);
        // Gray columns should be ignored → bounds match main content.
        expect(bounds!.left, 38);
        expect(bounds.right, 153);
      },
    );

    test(
      'ignores medium-length vertical noise runs below minRunLength threshold',
      () async {
        final image = _createBaseTestImage();

        // 5-pixel vertical noise runs at left and right edges.
        // The content height is 141 pixels, so minColumnRun = max(8, 2) = 8.
        // A run of 5 is below the threshold and should be ignored.
        for (int y = 80; y <= 84; y++) {
          image.setPixelRgb(5, y, 0, 0, 0);
        }
        for (int y = 80; y <= 84; y++) {
          image.setPixelRgb(190, y, 0, 0, 0);
        }

        final bounds = await MokuroParser.computeImageContentBoundsFromBytes(
          img.encodePng(image),
        );

        expect(bounds, isNotNull);
        // Noise runs should be ignored; bounds match main content.
        expect(bounds!.left, 38);
        expect(bounds.right, 153);
      },
    );

    test(
      'ignores page-number-like horizontal noise below the main content',
      () async {
        final image = _createBaseTestImage();

        // Simulated page number: 3px wide at row 190, columns 90–92.
        // The content width is 111 pixels, so minRowRun = max(8, 2) = 8.
        // A run of 3 is below the threshold and should be filtered by
        // Phase 3 row filtering.
        for (int x = 90; x <= 92; x++) {
          image.setPixelRgb(x, 190, 0, 0, 0);
        }

        final bounds = await MokuroParser.computeImageContentBoundsFromBytes(
          img.encodePng(image),
        );

        expect(bounds, isNotNull);
        // Top/bottom should match main content, ignoring page number.
        expect(bounds!.top, 28);
        expect(bounds.bottom, 173);
        // Left/right should also match main content.
        expect(bounds.left, 38);
        expect(bounds.right, 153);
      },
    );
  });
}
