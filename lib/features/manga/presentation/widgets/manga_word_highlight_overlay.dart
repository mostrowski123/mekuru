import 'package:flutter/material.dart';
import 'package:mekuru/features/manga/presentation/utils/crop_display_geometry.dart';

/// Draws the word-lookup highlight over a manga page.
///
/// [rects] are in image-pixel space and are mapped to screen space with the
/// same [scale], [offsetX], and [offsetY] the word tap overlay uses.
class MangaWordHighlightOverlay extends StatelessWidget {
  final List<Rect> rects;
  final double scale;
  final double offsetX;
  final double offsetY;

  const MangaWordHighlightOverlay({
    super.key,
    required this.rects,
    required this.scale,
    required this.offsetX,
    required this.offsetY,
  });

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final rect in rects) {
      final screenRect = imageRectToOverlay(
        rect,
        scale: scale,
        offsetX: offsetX,
        offsetY: offsetY,
      );
      if (screenRect.isEmpty) continue;

      children.add(
        Positioned.fromRect(
          rect: screenRect,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.cyan, width: 2),
              color: Colors.cyan.withAlpha(30),
            ),
          ),
        ),
      );
    }

    return IgnorePointer(child: Stack(children: children));
  }
}
