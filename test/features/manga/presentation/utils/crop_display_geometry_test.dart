import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/presentation/utils/crop_display_geometry.dart';

void main() {
  // ===================================================================
  // PageCropInsets
  // ===================================================================
  group('PageCropInsets', () {
    test('fromBounds computes correct insets', () {
      const imgW = 1000.0, imgH = 1500.0;
      final bounds = Rect.fromLTRB(100, 50, 900, 1450);
      final insets = PageCropInsets.fromBounds(bounds, imgW, imgH);

      expect(insets.left, 100.0);
      expect(insets.top, 50.0);
      expect(insets.right, 100.0); // 1000 - 900
      expect(insets.bottom, 50.0); // 1500 - 1450
    });

    test('fromBounds clamps negative insets to zero', () {
      const imgW = 1000.0, imgH = 1500.0;
      // Bounds that extend beyond the image
      final bounds = Rect.fromLTRB(-50, -20, 1050, 1520);
      final insets = PageCropInsets.fromBounds(bounds, imgW, imgH);

      expect(insets.left, 0.0); // clamped from -50
      expect(insets.top, 0.0); // clamped from -20
      expect(insets.right, 0.0); // clamped from -50
      expect(insets.bottom, 0.0); // clamped from -20
    });

    test('applyToImage round-trips with fromBounds', () {
      const imgW = 1000.0, imgH = 1500.0;
      final original = Rect.fromLTRB(100, 50, 900, 1450);
      final insets = PageCropInsets.fromBounds(original, imgW, imgH);
      final roundTripped = insets.applyToImage(imgW, imgH);

      expect(roundTripped.left, original.left);
      expect(roundTripped.top, original.top);
      expect(roundTripped.right, original.right);
      expect(roundTripped.bottom, original.bottom);
    });

    test('applyToImage with different dimensions produces valid rect', () {
      // Insets from a 1000×1500 image applied to a 2000×3000 image
      final insets = PageCropInsets(left: 100, top: 50, right: 100, bottom: 50);
      final rect = insets.applyToImage(2000, 3000);

      expect(rect.left, 100.0);
      expect(rect.top, 50.0);
      expect(rect.right, 1900.0); // 2000 - 100
      expect(rect.bottom, 2950.0); // 3000 - 50
    });

    test('applyToImage never produces inverted rect', () {
      // Insets so large they would invert the rect
      final insets = PageCropInsets(
        left: 600,
        top: 800,
        right: 600,
        bottom: 800,
      );
      final rect = insets.applyToImage(1000, 1500);

      // Right should be at least left, bottom should be at least top
      expect(rect.right, greaterThanOrEqualTo(rect.left));
      expect(rect.bottom, greaterThanOrEqualTo(rect.top));
    });

    test('zero insets produce full image rect', () {
      const imgW = 1000.0, imgH = 1500.0;
      const insets = PageCropInsets(left: 0, top: 0, right: 0, bottom: 0);
      final rect = insets.applyToImage(imgW, imgH);

      expect(rect, Rect.fromLTRB(0, 0, imgW, imgH));
    });
  });

  // ===================================================================
  // computeCropDisplayGeometry — single page
  // ===================================================================
  group('computeCropDisplayGeometry', () {
    test('content fills container width when width-constrained', () {
      // Container: 500×800, Image: 1000×1500
      // Content bounds: 200,100 → 800,600 (600×500)
      // scale = min(500/600, 800/500) = min(0.833, 1.6) = 0.833
      // Width is the constraining dimension
      final geo = computeCropDisplayGeometry(
        containerW: 500,
        containerH: 800,
        imgW: 1000,
        imgH: 1500,
        contentBounds: Rect.fromLTRB(200, 100, 800, 600),
      );

      final expectedScale = 500.0 / 600.0;
      expect(geo.scale, closeTo(expectedScale, 0.001));
      expect(geo.renderedRegionW, closeTo(500.0, 0.1));
      // Centered horizontally: offset should be ~0
      expect(geo.displayOffsetX, closeTo(0.0, 0.1));
    });

    test('content fills container height when height-constrained', () {
      // Container: 800×400, Image: 1000×1500
      // Content bounds: 200,100 → 800,1400 (600×1300)
      // Height-constrained: scale = 400/1300 = 0.3077
      final geo = computeCropDisplayGeometry(
        containerW: 800,
        containerH: 400,
        imgW: 1000,
        imgH: 1500,
        contentBounds: Rect.fromLTRB(200, 100, 800, 1400),
      );

      final expectedScale = 400.0 / 1300.0;
      expect(geo.scale, closeTo(expectedScale, 0.001));
      expect(geo.renderedRegionH, closeTo(400.0, 0.1));
      // Centered vertically: offset should be 0
      expect(geo.displayOffsetY, closeTo(0.0, 0.1));
    });

    test('content is centered in container', () {
      // Square container, non-square content
      // Container: 600×600, Image: 1000×1000
      // Content: 100,200 → 900,800 (800×600)
      // scale = min(600/800, 600/600) = 0.75
      final geo = computeCropDisplayGeometry(
        containerW: 600,
        containerH: 600,
        imgW: 1000,
        imgH: 1000,
        contentBounds: Rect.fromLTRB(100, 200, 900, 800),
      );

      final expectedScale = 600.0 / 800.0; // 0.75
      expect(geo.scale, closeTo(expectedScale, 0.001));

      final expectedRegionW = 800.0 * expectedScale; // 600
      final expectedRegionH = 600.0 * expectedScale; // 450
      expect(geo.renderedRegionW, closeTo(expectedRegionW, 0.1));
      expect(geo.renderedRegionH, closeTo(expectedRegionH, 0.1));

      // Centered
      expect(geo.displayOffsetX, closeTo((600 - expectedRegionW) / 2, 0.1));
      expect(geo.displayOffsetY, closeTo((600 - expectedRegionH) / 2, 0.1));
    });

    test('overlay offsets account for content bounds origin', () {
      // Container: 500×800, Image: 1000×1500
      // Content: 200,100 → 800,1400
      final geo = computeCropDisplayGeometry(
        containerW: 500,
        containerH: 800,
        imgW: 1000,
        imgH: 1500,
        contentBounds: Rect.fromLTRB(200, 100, 800, 1400),
      );

      // Overlay offsets map image-pixel coordinates to screen coordinates.
      // A word at image pixel (200, 100) should appear at (displayOffsetX, displayOffsetY).
      final wordScreenX = 200 * geo.scale + geo.overlayOffsetX;
      final wordScreenY = 100 * geo.scale + geo.overlayOffsetY;
      expect(wordScreenX, closeTo(geo.displayOffsetX, 0.1));
      expect(wordScreenY, closeTo(geo.displayOffsetY, 0.1));
    });

    test('clip translate positions content at origin of clip box', () {
      final geo = computeCropDisplayGeometry(
        containerW: 500,
        containerH: 800,
        imgW: 1000,
        imgH: 1500,
        contentBounds: Rect.fromLTRB(200, 100, 800, 1400),
      );

      // The clip translate should shift the image so the content region's
      // top-left corner aligns with the top-left of the clip box.
      expect(geo.clipTranslateX, closeTo(-200 * geo.scale, 0.1));
      expect(geo.clipTranslateY, closeTo(-100 * geo.scale, 0.1));
    });

    test('scaleOverride bypasses auto-computed scale', () {
      final geoAuto = computeCropDisplayGeometry(
        containerW: 500,
        containerH: 800,
        imgW: 1000,
        imgH: 1500,
        contentBounds: Rect.fromLTRB(200, 100, 800, 1400),
      );

      const overrideScale = 0.5;
      final geoOverride = computeCropDisplayGeometry(
        containerW: 500,
        containerH: 800,
        imgW: 1000,
        imgH: 1500,
        contentBounds: Rect.fromLTRB(200, 100, 800, 1400),
        scaleOverride: overrideScale,
      );

      expect(geoOverride.scale, overrideScale);
      expect(geoOverride.scale, isNot(closeTo(geoAuto.scale, 0.001)));

      // Region dimensions should use override scale
      expect(geoOverride.renderedRegionW, closeTo(600 * overrideScale, 0.1));
      expect(geoOverride.renderedRegionH, closeTo(1300 * overrideScale, 0.1));
    });

    test('full-image content bounds behave like uncropped', () {
      // Content bounds that cover the entire image
      final geo = computeCropDisplayGeometry(
        containerW: 500,
        containerH: 800,
        imgW: 1000,
        imgH: 1500,
        contentBounds: Rect.fromLTRB(0, 0, 1000, 1500),
      );

      // Should behave identically to BoxFit.contain
      final expectedScale = 500.0 / 1000.0; // min(500/1000, 800/1500)
      expect(geo.scale, closeTo(expectedScale, 0.001));
      expect(geo.clipTranslateX, closeTo(0.0, 0.001));
      expect(geo.clipTranslateY, closeTo(0.0, 0.001));
      expect(geo.overlayOffsetX, closeTo(geo.displayOffsetX, 0.001));
      expect(geo.overlayOffsetY, closeTo(geo.displayOffsetY, 0.001));
    });

    test('prevents white gutters on height-constrained single page', () {
      // This is the regression test for the original white-gutter bug.
      // Container: 400 wide × 800 tall, Image: 1000×1500
      // Content: 100,50 → 900,1450 (800×1400)
      // Width-constrained: 400/800 = 0.5; height: 400/1400 = 0.2857
      // Height is the constraining dimension → scale = 0.2857
      // At this scale, content region is 228.6×400 — fits within 400×800
      // The displayed region should match renderedRegionW exactly.
      final geo = computeCropDisplayGeometry(
        containerW: 400,
        containerH: 800,
        imgW: 1000,
        imgH: 1500,
        contentBounds: Rect.fromLTRB(100, 50, 900, 1450),
      );

      // Verify rendered region fits within container
      expect(geo.renderedRegionW, lessThanOrEqualTo(400.0 + 0.01));
      expect(geo.renderedRegionH, lessThanOrEqualTo(800.0 + 0.01));

      // Verify the clip region doesn't extend beyond the container
      // (which would cause white gutters)
      final rightEdge = geo.displayOffsetX + geo.renderedRegionW;
      final bottomEdge = geo.displayOffsetY + geo.renderedRegionH;
      expect(rightEdge, lessThanOrEqualTo(400.0 + 0.01));
      expect(bottomEdge, lessThanOrEqualTo(800.0 + 0.01));
    });

    test('narrow content crop fills available width', () {
      // Tall narrow content — like a manga page with wide margins
      // Container: 500×800, Image: 1000×1500
      // Content: 400,100 → 600,1400 (200×1300)
      // Width-constrained: 500/200 = 2.5; Height: 800/1300 = 0.615
      // Height is constraining → scale = 0.615
      final geo = computeCropDisplayGeometry(
        containerW: 500,
        containerH: 800,
        imgW: 1000,
        imgH: 1500,
        contentBounds: Rect.fromLTRB(400, 100, 600, 1400),
      );

      // Rendered height should fill the container
      expect(geo.renderedRegionH, closeTo(800.0, 0.1));
      // Rendered width should be less than container
      expect(geo.renderedRegionW, lessThan(500.0));
      // Content should be horizontally centered
      expect(geo.displayOffsetX,
          closeTo((500.0 - geo.renderedRegionW) / 2, 0.1));
    });
  });

  // ===================================================================
  // computeSharedCropBounds — two-page spread
  // ===================================================================
  group('computeSharedCropBounds', () {
    test('returns null pair when either bounds is null', () {
      final (left, right) = computeSharedCropBounds(
        leftContentBounds: Rect.fromLTRB(100, 50, 900, 1450),
        rightContentBounds: null,
        leftImgW: 1000,
        leftImgH: 1500,
        rightImgW: 1000,
        rightImgH: 1500,
      );
      expect(left, isNull);
      expect(right, isNull);

      final (left2, right2) = computeSharedCropBounds(
        leftContentBounds: null,
        rightContentBounds: Rect.fromLTRB(100, 50, 900, 1450),
        leftImgW: 1000,
        leftImgH: 1500,
        rightImgW: 1000,
        rightImgH: 1500,
      );
      expect(left2, isNull);
      expect(right2, isNull);
    });

    test('produces same-height crops for same-dimension pages', () {
      // Two pages with different content bounds but same image dimensions
      final (leftCrop, rightCrop) = computeSharedCropBounds(
        leftContentBounds: Rect.fromLTRB(100, 80, 900, 1420),
        rightContentBounds: Rect.fromLTRB(50, 120, 950, 1380),
        leftImgW: 1000,
        leftImgH: 1500,
        rightImgW: 1000,
        rightImgH: 1500,
      );

      expect(leftCrop, isNotNull);
      expect(rightCrop, isNotNull);

      // Heights should be identical (the core invariant for spread alignment)
      expect(leftCrop!.height, closeTo(rightCrop!.height, 0.001));
    });

    test('uses tighter top/bottom insets (min of both pages)', () {
      // Left has 80px top margin, right has 120px → shared should use 80px
      // Left has 80px bottom margin (1500-1420), right has 120px → shared uses 80px
      final (leftCrop, rightCrop) = computeSharedCropBounds(
        leftContentBounds: Rect.fromLTRB(100, 80, 900, 1420),
        rightContentBounds: Rect.fromLTRB(50, 120, 950, 1380),
        leftImgW: 1000,
        leftImgH: 1500,
        rightImgW: 1000,
        rightImgH: 1500,
      );

      // Shared top = min(80, 120) = 80
      expect(leftCrop!.top, closeTo(80.0, 0.001));
      expect(rightCrop!.top, closeTo(80.0, 0.001));

      // Shared bottom = min(80, 120) = 80 → bottom edge = 1500 - 80 = 1420
      expect(leftCrop.bottom, closeTo(1420.0, 0.001));
      expect(rightCrop.bottom, closeTo(1420.0, 0.001));
    });

    test('shares inner-edge inset (gutter between pages)', () {
      // Left page: right inset = 1000 - 900 = 100
      // Right page: left inset = 50
      // Shared inner = min(100, 50) = 50
      final (leftCrop, rightCrop) = computeSharedCropBounds(
        leftContentBounds: Rect.fromLTRB(100, 80, 900, 1420),
        rightContentBounds: Rect.fromLTRB(50, 120, 950, 1380),
        leftImgW: 1000,
        leftImgH: 1500,
        rightImgW: 1000,
        rightImgH: 1500,
      );

      // Left's right edge uses shared inner inset: 1000 - 50 = 950
      expect(leftCrop!.right, closeTo(950.0, 0.001));
      // Right's left edge uses shared inner inset: 50
      expect(rightCrop!.left, closeTo(50.0, 0.001));
    });

    test('preserves outer-edge insets (left of left page, right of right page)',
        () {
      final (leftCrop, rightCrop) = computeSharedCropBounds(
        leftContentBounds: Rect.fromLTRB(100, 80, 900, 1420),
        rightContentBounds: Rect.fromLTRB(50, 120, 950, 1380),
        leftImgW: 1000,
        leftImgH: 1500,
        rightImgW: 1000,
        rightImgH: 1500,
      );

      // Left page keeps its own left inset: 100
      expect(leftCrop!.left, closeTo(100.0, 0.001));
      // Right page keeps its own right inset: 1000 - 950 = 50 → right = 950
      expect(rightCrop!.right, closeTo(950.0, 0.001));
    });

    test('handles identical content bounds', () {
      final bounds = Rect.fromLTRB(150, 100, 850, 1400);
      final (leftCrop, rightCrop) = computeSharedCropBounds(
        leftContentBounds: bounds,
        rightContentBounds: bounds,
        leftImgW: 1000,
        leftImgH: 1500,
        rightImgW: 1000,
        rightImgH: 1500,
      );

      expect(leftCrop, isNotNull);
      expect(rightCrop, isNotNull);
      // With identical bounds on same-size images, crops should be identical
      expect(leftCrop!.left, closeTo(rightCrop!.left, 0.001));
      expect(leftCrop.top, closeTo(rightCrop.top, 0.001));
      expect(leftCrop.right, closeTo(rightCrop.right, 0.001));
      expect(leftCrop.bottom, closeTo(rightCrop.bottom, 0.001));
    });

    test('handles different image dimensions', () {
      // Pages with slightly different dimensions (e.g. scanned at different DPIs)
      final (leftCrop, rightCrop) = computeSharedCropBounds(
        leftContentBounds: Rect.fromLTRB(100, 50, 900, 1450),
        rightContentBounds: Rect.fromLTRB(110, 55, 990, 1595),
        leftImgW: 1000,
        leftImgH: 1500,
        rightImgW: 1100,
        rightImgH: 1650,
      );

      expect(leftCrop, isNotNull);
      expect(rightCrop, isNotNull);
      // Both should produce valid rects
      expect(leftCrop!.width, greaterThan(0));
      expect(leftCrop.height, greaterThan(0));
      expect(rightCrop!.width, greaterThan(0));
      expect(rightCrop.height, greaterThan(0));
    });
  });

  // ===================================================================
  // computeSharedScale — two-page spread
  // ===================================================================
  group('computeSharedScale', () {
    test('uses minimum of both pages scales', () {
      // Left crop: 600×1300, right crop: 700×1300
      // Half width: 400, max height: 800
      // Left: min(400/600, 800/1300) = min(0.667, 0.615) = 0.615
      // Right: min(400/700, 800/1300) = min(0.571, 0.615) = 0.571
      // Shared: min(0.615, 0.571) = 0.571
      final scale = computeSharedScale(
        leftCrop: Rect.fromLTRB(200, 100, 800, 1400), // 600×1300
        rightCrop: Rect.fromLTRB(150, 100, 850, 1400), // 700×1300
        halfWidth: 400,
        maxHeight: 800,
      );

      // Right page is wider, so its scale is smaller → shared scale
      final rightScale = 400.0 / 700.0; // 0.571
      expect(scale, closeTo(rightScale, 0.001));
    });

    test('both pages display at same height with shared scale', () {
      final leftCrop = Rect.fromLTRB(200, 100, 800, 1400); // 600×1300
      final rightCrop = Rect.fromLTRB(150, 100, 850, 1400); // 700×1300
      const halfWidth = 400.0;
      const maxHeight = 800.0;

      final scale = computeSharedScale(
        leftCrop: leftCrop,
        rightCrop: rightCrop,
        halfWidth: halfWidth,
        maxHeight: maxHeight,
      );

      // Both should produce the same displayed height
      final leftDisplayH = leftCrop.height * scale;
      final rightDisplayH = rightCrop.height * scale;
      expect(leftDisplayH, closeTo(rightDisplayH, 0.001));
    });

    test('both pages fit within their half-width allocation', () {
      final leftCrop = Rect.fromLTRB(200, 100, 800, 1400);
      final rightCrop = Rect.fromLTRB(50, 100, 950, 1400);
      const halfWidth = 400.0;
      const maxHeight = 800.0;

      final scale = computeSharedScale(
        leftCrop: leftCrop,
        rightCrop: rightCrop,
        halfWidth: halfWidth,
        maxHeight: maxHeight,
      );

      expect(leftCrop.width * scale, lessThanOrEqualTo(halfWidth + 0.01));
      expect(rightCrop.width * scale, lessThanOrEqualTo(halfWidth + 0.01));
      expect(leftCrop.height * scale, lessThanOrEqualTo(maxHeight + 0.01));
      expect(rightCrop.height * scale, lessThanOrEqualTo(maxHeight + 0.01));
    });

    test('equal-width crops produce same scale as individual fit', () {
      final crop = Rect.fromLTRB(100, 50, 900, 1450); // 800×1400
      const halfWidth = 400.0;
      const maxHeight = 800.0;

      final sharedScale = computeSharedScale(
        leftCrop: crop,
        rightCrop: crop,
        halfWidth: halfWidth,
        maxHeight: maxHeight,
      );

      // Individual BoxFit.contain for each half
      final individualScale = 400.0 / 800.0; // min(400/800, 800/1400) = 0.5
      expect(sharedScale, closeTo(individualScale, 0.001));
    });

    test('height-constrained pages produce correct shared scale', () {
      // Very wide crops where height is the constraint
      final leftCrop = Rect.fromLTRB(0, 200, 300, 1300); // 300×1100
      final rightCrop = Rect.fromLTRB(0, 200, 350, 1300); // 350×1100
      const halfWidth = 400.0;
      const maxHeight = 600.0;

      final scale = computeSharedScale(
        leftCrop: leftCrop,
        rightCrop: rightCrop,
        halfWidth: halfWidth,
        maxHeight: maxHeight,
      );

      // Both fit width-wise, so height determines: 600/1100 = 0.545
      final expectedScale = 600.0 / 1100.0;
      expect(scale, closeTo(expectedScale, 0.001));
    });
  });

  // ===================================================================
  // Integration: computeSharedCropBounds + computeSharedScale +
  //              computeCropDisplayGeometry
  // ===================================================================
  group('Spread display integration', () {
    test('full pipeline produces aligned, non-overlapping pages', () {
      // Simulate a complete two-page spread layout
      const imgW = 1000.0, imgH = 1500.0;
      const containerW = 800.0, containerH = 600.0;
      const halfWidth = containerW / 2;

      final (leftCrop, rightCrop) = computeSharedCropBounds(
        leftContentBounds: Rect.fromLTRB(100, 80, 900, 1420),
        rightContentBounds: Rect.fromLTRB(60, 120, 940, 1380),
        leftImgW: imgW,
        leftImgH: imgH,
        rightImgW: imgW,
        rightImgH: imgH,
      );

      expect(leftCrop, isNotNull);
      expect(rightCrop, isNotNull);

      final sharedScale = computeSharedScale(
        leftCrop: leftCrop!,
        rightCrop: rightCrop!,
        halfWidth: halfWidth,
        maxHeight: containerH,
      );

      final leftGeo = computeCropDisplayGeometry(
        containerW: halfWidth,
        containerH: containerH,
        imgW: imgW,
        imgH: imgH,
        contentBounds: leftCrop,
        scaleOverride: sharedScale,
      );

      final rightGeo = computeCropDisplayGeometry(
        containerW: halfWidth,
        containerH: containerH,
        imgW: imgW,
        imgH: imgH,
        contentBounds: rightCrop,
        scaleOverride: sharedScale,
      );

      // Both pages use the same scale
      expect(leftGeo.scale, equals(rightGeo.scale));

      // Both rendered regions have the same height (aligned tops/bottoms)
      expect(leftGeo.renderedRegionH,
          closeTo(rightGeo.renderedRegionH, 0.001));

      // Both vertical offsets match (aligned vertically)
      expect(leftGeo.displayOffsetY,
          closeTo(rightGeo.displayOffsetY, 0.001));

      // Both fit within their half-width container
      expect(leftGeo.renderedRegionW, lessThanOrEqualTo(halfWidth + 0.01));
      expect(rightGeo.renderedRegionW, lessThanOrEqualTo(halfWidth + 0.01));

      // Both fit within the container height
      expect(leftGeo.renderedRegionH, lessThanOrEqualTo(containerH + 0.01));
      expect(rightGeo.renderedRegionH, lessThanOrEqualTo(containerH + 0.01));
    });

    test('spread with asymmetric crops still aligns vertically', () {
      // One page has heavy cropping, the other has minimal
      const imgW = 1000.0, imgH = 1500.0;
      const containerW = 1000.0, containerH = 700.0;
      const halfWidth = containerW / 2;

      final (leftCrop, rightCrop) = computeSharedCropBounds(
        leftContentBounds: Rect.fromLTRB(300, 200, 700, 1300), // heavy crop
        rightContentBounds: Rect.fromLTRB(50, 50, 950, 1450), // light crop
        leftImgW: imgW,
        leftImgH: imgH,
        rightImgW: imgW,
        rightImgH: imgH,
      );

      final sharedScale = computeSharedScale(
        leftCrop: leftCrop!,
        rightCrop: rightCrop!,
        halfWidth: halfWidth,
        maxHeight: containerH,
      );

      final leftGeo = computeCropDisplayGeometry(
        containerW: halfWidth,
        containerH: containerH,
        imgW: imgW,
        imgH: imgH,
        contentBounds: leftCrop,
        scaleOverride: sharedScale,
      );

      final rightGeo = computeCropDisplayGeometry(
        containerW: halfWidth,
        containerH: containerH,
        imgW: imgW,
        imgH: imgH,
        contentBounds: rightCrop,
        scaleOverride: sharedScale,
      );

      // Heights still match despite asymmetric crops
      expect(leftGeo.renderedRegionH,
          closeTo(rightGeo.renderedRegionH, 0.001));
      // Vertical alignment
      expect(leftGeo.displayOffsetY,
          closeTo(rightGeo.displayOffsetY, 0.001));
    });

    test('word overlay at content origin maps to display offset', () {
      // Verify word overlay positioning is correct after crop transform
      const containerW = 500.0, containerH = 800.0;
      final contentBounds = Rect.fromLTRB(150, 100, 850, 1400);

      final geo = computeCropDisplayGeometry(
        containerW: containerW,
        containerH: containerH,
        imgW: 1000,
        imgH: 1500,
        contentBounds: contentBounds,
      );

      // A word at the content origin should map to the display position
      final wordAtOriginX = contentBounds.left * geo.scale + geo.overlayOffsetX;
      final wordAtOriginY = contentBounds.top * geo.scale + geo.overlayOffsetY;

      expect(wordAtOriginX, closeTo(geo.displayOffsetX, 0.1));
      expect(wordAtOriginY, closeTo(geo.displayOffsetY, 0.1));

      // A word at the content bottom-right should map to the far edge
      final wordAtEndX = contentBounds.right * geo.scale + geo.overlayOffsetX;
      final wordAtEndY = contentBounds.bottom * geo.scale + geo.overlayOffsetY;

      expect(wordAtEndX,
          closeTo(geo.displayOffsetX + geo.renderedRegionW, 0.1));
      expect(wordAtEndY,
          closeTo(geo.displayOffsetY + geo.renderedRegionH, 0.1));
    });
  });

  // ===================================================================
  // Edge cases
  // ===================================================================
  group('Edge cases', () {
    test('very small content region in large image', () {
      // A tiny content area — e.g. a single panel in a mostly-blank page
      final geo = computeCropDisplayGeometry(
        containerW: 500,
        containerH: 800,
        imgW: 2000,
        imgH: 3000,
        contentBounds: Rect.fromLTRB(900, 1400, 1100, 1600), // 200×200
      );

      // Should scale up to fill width or height
      expect(geo.scale, greaterThan(1.0));
      expect(geo.renderedRegionW, lessThanOrEqualTo(500.0 + 0.01));
      expect(geo.renderedRegionH, lessThanOrEqualTo(800.0 + 0.01));
    });

    test('content bounds equal to full image', () {
      final geo = computeCropDisplayGeometry(
        containerW: 400,
        containerH: 600,
        imgW: 1000,
        imgH: 1500,
        contentBounds: Rect.fromLTRB(0, 0, 1000, 1500),
      );

      // No cropping needed — just BoxFit.contain
      expect(geo.clipTranslateX, closeTo(0.0, 0.001));
      expect(geo.clipTranslateY, closeTo(0.0, 0.001));
    });

    test('extreme aspect ratio (very wide content)', () {
      final geo = computeCropDisplayGeometry(
        containerW: 500,
        containerH: 800,
        imgW: 2000,
        imgH: 100,
        contentBounds: Rect.fromLTRB(100, 10, 1900, 90), // 1800×80
      );

      // Width-constrained
      final expectedScale = 500.0 / 1800.0;
      expect(geo.scale, closeTo(expectedScale, 0.001));
      expect(geo.renderedRegionW, closeTo(500.0, 0.1));
    });

    test('extreme aspect ratio (very tall content)', () {
      final geo = computeCropDisplayGeometry(
        containerW: 500,
        containerH: 800,
        imgW: 100,
        imgH: 3000,
        contentBounds: Rect.fromLTRB(10, 100, 90, 2900), // 80×2800
      );

      // Height-constrained
      final expectedScale = 800.0 / 2800.0;
      expect(geo.scale, closeTo(expectedScale, 0.001));
      expect(geo.renderedRegionH, closeTo(800.0, 0.1));
    });

    test('square container and square content', () {
      final geo = computeCropDisplayGeometry(
        containerW: 500,
        containerH: 500,
        imgW: 1000,
        imgH: 1000,
        contentBounds: Rect.fromLTRB(100, 100, 900, 900), // 800×800
      );

      final expectedScale = 500.0 / 800.0;
      expect(geo.scale, closeTo(expectedScale, 0.001));
      // Should be centered both ways
      expect(geo.displayOffsetX, closeTo(0.0, 0.1));
      expect(geo.displayOffsetY, closeTo(0.0, 0.1));
    });
  });
}
