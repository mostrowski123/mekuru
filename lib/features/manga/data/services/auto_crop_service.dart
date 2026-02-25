import 'dart:io';
import 'dart:isolate';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Detects content bounds in manga page images for auto-cropping.
///
/// Scans from each edge inward to find the first row/column with
/// non-background content, producing a [Rect] that tightly wraps the
/// drawn content. This allows the reader to zoom in on the content
/// area, removing empty margins.
class AutoCropService {
  const AutoCropService._();

  /// Compute content bounds for a single image.
  /// Returns `null` if the image can't be decoded or is entirely uniform.
  ///
  /// Runs synchronously — call via [Isolate.run] for background processing.
  static Rect? computeContentBounds(String imagePath) {
    try {
      final bytes = File(imagePath).readAsBytesSync();
      final image = img.decodeImage(bytes);
      if (image == null) return null;

      return _findContentRect(image);
    } catch (e) {
      debugPrint('[AutoCrop] Failed to process $imagePath: $e');
      return null;
    }
  }

  /// Compute content bounds for all pages in parallel using isolates.
  static Future<List<Rect?>> computeAllBounds(List<String> imagePaths) async {
    final results = <Rect?>[];
    // Process in batches to avoid spawning too many isolates
    const batchSize = 4;
    for (int i = 0; i < imagePaths.length; i += batchSize) {
      final batch = imagePaths.sublist(
        i,
        i + batchSize > imagePaths.length ? imagePaths.length : i + batchSize,
      );
      final batchResults = await Future.wait(
        batch.map((path) => Isolate.run(() => computeContentBounds(path))),
      );
      results.addAll(batchResults);
    }
    return results;
  }

  /// Find the tightest rectangle containing non-background content.
  ///
  /// Samples pixels along each edge, moving inward until a row/column
  /// with significantly different pixels is found. Uses a luminance
  /// threshold to handle near-white and near-black backgrounds.
  static Rect? _findContentRect(img.Image image) {
    final w = image.width;
    final h = image.height;
    if (w == 0 || h == 0) return null;

    // Determine background color from corner samples
    final bgLum = _estimateBackgroundLuminance(image);

    // Threshold: a pixel differs from background if its luminance
    // is more than this far from the background luminance.
    const threshold = 30;

    // Minimum percentage of non-background pixels in a row/column
    // for it to be considered "content". Prevents noise from
    // triggering early detection.
    const contentRatio = 0.02; // 2% of pixels must differ
    final minContentPixelsH = (w * contentRatio).ceil();
    final minContentPixelsV = (h * contentRatio).ceil();

    // Scan from each edge
    int top = 0;
    int bottom = h - 1;
    int left = 0;
    int right = w - 1;

    // Top edge: scan rows downward
    for (int y = 0; y < h; y++) {
      if (_rowHasContent(image, y, bgLum, threshold, minContentPixelsH)) {
        top = y;
        break;
      }
    }

    // Bottom edge: scan rows upward
    for (int y = h - 1; y >= top; y--) {
      if (_rowHasContent(image, y, bgLum, threshold, minContentPixelsH)) {
        bottom = y;
        break;
      }
    }

    // Left edge: scan columns rightward
    for (int x = 0; x < w; x++) {
      if (_colHasContent(image, x, top, bottom, bgLum, threshold,
          minContentPixelsV)) {
        left = x;
        break;
      }
    }

    // Right edge: scan columns leftward
    for (int x = w - 1; x >= left; x--) {
      if (_colHasContent(image, x, top, bottom, bgLum, threshold,
          minContentPixelsV)) {
        right = x;
        break;
      }
    }

    // Add a small padding (1% of dimensions)
    final padX = (w * 0.01).round();
    final padY = (h * 0.01).round();
    left = (left - padX).clamp(0, w - 1);
    top = (top - padY).clamp(0, h - 1);
    right = (right + padX).clamp(0, w - 1);
    bottom = (bottom + padY).clamp(0, h - 1);

    // If the content rect is nearly the full image, return null (no crop needed)
    final contentArea = (right - left) * (bottom - top);
    final totalArea = w * h;
    if (contentArea > totalArea * 0.95) return null;

    return Rect.fromLTRB(
      left.toDouble(),
      top.toDouble(),
      right.toDouble(),
      bottom.toDouble(),
    );
  }

  /// Estimate the background luminance by sampling corner pixels.
  static int _estimateBackgroundLuminance(img.Image image) {
    final samples = <int>[];
    final corners = [
      [0, 0],
      [image.width - 1, 0],
      [0, image.height - 1],
      [image.width - 1, image.height - 1],
    ];
    for (final c in corners) {
      samples.add(_pixelLuminance(image, c[0], c[1]));
    }
    samples.sort();
    // Use median of corners
    return samples[samples.length ~/ 2];
  }

  /// Get luminance of a pixel (0-255).
  static int _pixelLuminance(img.Image image, int x, int y) {
    final pixel = image.getPixel(x, y);
    // Standard luminance formula
    return (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b).round();
  }

  /// Check if a row has enough non-background pixels.
  static bool _rowHasContent(
    img.Image image,
    int y,
    int bgLum,
    int threshold,
    int minPixels,
  ) {
    int count = 0;
    // Sample every 4th pixel for speed
    for (int x = 0; x < image.width; x += 4) {
      final lum = _pixelLuminance(image, x, y);
      if ((lum - bgLum).abs() > threshold) {
        count++;
        if (count >= minPixels) return true;
      }
    }
    return false;
  }

  /// Check if a column (within y range) has enough non-background pixels.
  static bool _colHasContent(
    img.Image image,
    int x,
    int yStart,
    int yEnd,
    int bgLum,
    int threshold,
    int minPixels,
  ) {
    int count = 0;
    for (int y = yStart; y <= yEnd; y += 4) {
      final lum = _pixelLuminance(image, x, y);
      if ((lum - bgLum).abs() > threshold) {
        count++;
        if (count >= minPixels) return true;
      }
    }
    return false;
  }
}
