import 'package:flutter/material.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';

/// Renders invisible tap targets over each [MokuroWord] in the given blocks.
///
/// Coordinates are transformed from image-pixel space to screen space using
/// [scale], [offsetX], and [offsetY] (computed from `BoxFit.contain` layout).
///
/// In debug mode, draws semi-transparent rectangles around each word for
/// visual verification of bounding box accuracy.
class MangaWordOverlay extends StatelessWidget {
  final List<MokuroTextBlock> blocks;
  final double scale;
  final double offsetX;
  final double offsetY;
  final bool debugMode;
  final void Function(
    MokuroWord word,
    MokuroTextBlock block,
    Offset globalPosition,
  )? onWordTapped;

  const MangaWordOverlay({
    super.key,
    required this.blocks,
    required this.scale,
    required this.offsetX,
    required this.offsetY,
    this.debugMode = false,
    this.onWordTapped,
  });

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];

    for (final block in blocks) {
      for (final word in block.words) {
        final bbox = word.boundingBox;
        final left = bbox.left * scale + offsetX;
        final top = bbox.top * scale + offsetY;
        final width = bbox.width * scale;
        final height = bbox.height * scale;

        // Skip words with degenerate bounding boxes
        if (width <= 0 || height <= 0) continue;

        children.add(Positioned(
          left: left,
          top: top,
          width: width,
          height: height,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) {
              onWordTapped?.call(word, block, details.globalPosition);
            },
            child: debugMode
                ? Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.red.withValues(alpha: 0.5),
                      ),
                      color: Colors.red.withValues(alpha: 0.1),
                    ),
                    alignment: Alignment.center,
                    child: FittedBox(
                      child: Text(
                        word.surface,
                        style:
                            const TextStyle(color: Colors.red, fontSize: 8),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ));
      }
    }

    return Stack(children: children);
  }
}
