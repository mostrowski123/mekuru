import 'dart:math' as math;
import 'dart:ui' show Rect;

/// Pure geometry computations for manga page crop display.
///
/// Extracted from widget build methods so the layout logic is fully
/// unit-testable without pumping widgets.

// ---------------------------------------------------------------------------
// PageCropInsets — maps content bounds ↔ edge insets
// ---------------------------------------------------------------------------

/// Describes the insets from the edge of a page image to its content bounds.
class PageCropInsets {
  final double left;
  final double top;
  final double right;
  final double bottom;

  const PageCropInsets({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  /// Derives insets from a content-bounds [Rect] relative to the full image.
  factory PageCropInsets.fromBounds(
    Rect contentBounds,
    double imgW,
    double imgH,
  ) {
    return PageCropInsets(
      left: contentBounds.left.clamp(0.0, imgW),
      top: contentBounds.top.clamp(0.0, imgH),
      right: (imgW - contentBounds.right).clamp(0.0, imgW),
      bottom: (imgH - contentBounds.bottom).clamp(0.0, imgH),
    );
  }

  /// Converts insets back to a crop [Rect] for the given image dimensions.
  Rect applyToImage(double imgW, double imgH) {
    final cropLeft = left.clamp(0.0, imgW);
    final cropTop = top.clamp(0.0, imgH);
    final cropRight = math.max(cropLeft, imgW - right.clamp(0.0, imgW));
    final cropBottom = math.max(cropTop, imgH - bottom.clamp(0.0, imgH));
    return Rect.fromLTRB(cropLeft, cropTop, cropRight, cropBottom);
  }
}

// ---------------------------------------------------------------------------
// CropDisplayGeometry — single-page layout result
// ---------------------------------------------------------------------------

/// All computed values needed to render a single auto-cropped manga page.
class CropDisplayGeometry {
  /// Scale factor applied to the image.
  final double scale;

  /// Top-left of the clipped content region inside the container.
  final double displayOffsetX;
  final double displayOffsetY;

  /// Pixel dimensions of the clipped content region on screen.
  final double renderedRegionW;
  final double renderedRegionH;

  /// Offset used by word overlays (maps image-pixel → screen coords).
  final double overlayOffsetX;
  final double overlayOffsetY;

  /// Translation applied to the full image inside the clip box so the
  /// content-bounds region aligns with the visible area.
  final double clipTranslateX;
  final double clipTranslateY;

  const CropDisplayGeometry({
    required this.scale,
    required this.displayOffsetX,
    required this.displayOffsetY,
    required this.renderedRegionW,
    required this.renderedRegionH,
    required this.overlayOffsetX,
    required this.overlayOffsetY,
    required this.clipTranslateX,
    required this.clipTranslateY,
  });
}

/// Computes the layout geometry for displaying an auto-cropped manga page.
///
/// The image is scaled so that [contentBounds] fits within the container, then
/// positioned so only the content region is visible (via a clip + translate).
CropDisplayGeometry computeCropDisplayGeometry({
  required double containerW,
  required double containerH,
  required double imgW,
  required double imgH,
  required Rect contentBounds,
  double? scaleOverride,
}) {
  final regionW = contentBounds.width;
  final regionH = contentBounds.height;

  final scale = scaleOverride ??
      math.min(containerW / regionW, containerH / regionH);

  final renderedRegionW = regionW * scale;
  final renderedRegionH = regionH * scale;
  final displayOffsetX = (containerW - renderedRegionW) / 2;
  final displayOffsetY = (containerH - renderedRegionH) / 2;

  final overlayOffsetX = displayOffsetX - contentBounds.left * scale;
  final overlayOffsetY = displayOffsetY - contentBounds.top * scale;

  final clipTranslateX = -contentBounds.left * scale;
  final clipTranslateY = -contentBounds.top * scale;

  return CropDisplayGeometry(
    scale: scale,
    displayOffsetX: displayOffsetX,
    displayOffsetY: displayOffsetY,
    renderedRegionW: renderedRegionW,
    renderedRegionH: renderedRegionH,
    overlayOffsetX: overlayOffsetX,
    overlayOffsetY: overlayOffsetY,
    clipTranslateX: clipTranslateX,
    clipTranslateY: clipTranslateY,
  );
}

// ---------------------------------------------------------------------------
// Spread helpers — shared crop bounds & shared scale
// ---------------------------------------------------------------------------

/// Computes shared crop bounds for a two-page spread.
///
/// Both pages receive the same top/bottom insets (tighter of the two) and a
/// shared inner-edge inset, while keeping their own outer-edge insets.
/// This ensures both crops have the **same height** when image dimensions
/// match, which is a prerequisite for the shared-scale approach.
(Rect?, Rect?) computeSharedCropBounds({
  required Rect? leftContentBounds,
  required Rect? rightContentBounds,
  required double leftImgW,
  required double leftImgH,
  required double rightImgW,
  required double rightImgH,
}) {
  if (leftContentBounds == null || rightContentBounds == null) {
    return (null, null);
  }

  final leftInsets = PageCropInsets.fromBounds(
    leftContentBounds, leftImgW, leftImgH,
  );
  final rightInsets = PageCropInsets.fromBounds(
    rightContentBounds, rightImgW, rightImgH,
  );

  final sharedTop = math.min(leftInsets.top, rightInsets.top);
  final sharedBottom = math.min(leftInsets.bottom, rightInsets.bottom);
  final sharedInner = math.min(leftInsets.right, rightInsets.left);

  return (
    PageCropInsets(
      left: leftInsets.left,
      top: sharedTop,
      right: sharedInner,
      bottom: sharedBottom,
    ).applyToImage(leftImgW, leftImgH),
    PageCropInsets(
      left: sharedInner,
      top: sharedTop,
      right: rightInsets.right,
      bottom: sharedBottom,
    ).applyToImage(rightImgW, rightImgH),
  );
}

/// Computes a shared scale factor for a two-page spread so both pages
/// display at the same height.
///
/// Takes the minimum of both pages' BoxFit.contain scales so both fit
/// within their half-width allocation.
double computeSharedScale({
  required Rect leftCrop,
  required Rect rightCrop,
  required double halfWidth,
  required double maxHeight,
}) {
  final leftScale = math.min(
    halfWidth / leftCrop.width,
    maxHeight / leftCrop.height,
  );
  final rightScale = math.min(
    halfWidth / rightCrop.width,
    maxHeight / rightCrop.height,
  );
  return math.min(leftScale, rightScale);
}
