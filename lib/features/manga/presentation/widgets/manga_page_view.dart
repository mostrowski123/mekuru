import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/presentation/widgets/manga_word_overlay.dart';

/// Renders a single manga page image with pinch-to-zoom and word tap targets.
///
/// Uses [InteractiveViewer] for zoom/pan. A [LayoutBuilder] computes the
/// `BoxFit.contain` scale and offset so the [MangaWordOverlay] positions
/// match the rendered image exactly.
///
/// Reports zoom state changes via [onZoomChanged] so the parent
/// [PageView] can disable swiping when the user is zoomed in.
class MangaPageView extends StatefulWidget {
  final MokuroPage page;
  final String imageDirPath;
  final bool debugOverlay;
  final MokuroWord? highlightedWord;
  final void Function(
    MokuroWord word,
    MokuroTextBlock block,
    Offset globalPosition,
  )? onWordTapped;
  final ValueChanged<bool>? onZoomChanged;

  const MangaPageView({
    super.key,
    required this.page,
    required this.imageDirPath,
    this.debugOverlay = false,
    this.highlightedWord,
    this.onWordTapped,
    this.onZoomChanged,
  });

  @override
  State<MangaPageView> createState() => _MangaPageViewState();
}

class _MangaPageViewState extends State<MangaPageView> {
  late final TransformationController _transformController;
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    _transformController = TransformationController();
    _transformController.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _transformController.removeListener(_onTransformChanged);
    _transformController.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final scale = _transformController.value.getMaxScaleOnAxis();
    final zoomed = scale > 1.05; // small tolerance to avoid float jitter
    if (zoomed != _isZoomed) {
      _isZoomed = zoomed;
      widget.onZoomChanged?.call(zoomed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final imagePath =
        '${widget.imageDirPath}/${widget.page.imageFileName}';

    return InteractiveViewer(
      transformationController: _transformController,
      minScale: 1.0,
      maxScale: 5.0,
      // Allow panning only when zoomed in so single-finger
      // gestures pass through to the PageView when at 1x.
      panEnabled: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final containerW = constraints.maxWidth;
          final containerH = constraints.maxHeight;
          final imgW = widget.page.imgWidth.toDouble();
          final imgH = widget.page.imgHeight.toDouble();

          // BoxFit.contain scale and centering offset
          final scale = (imgW == 0 || imgH == 0)
              ? 1.0
              : (containerW / imgW).clamp(0.0, containerH / imgH) < containerH / imgH
                  ? containerW / imgW
                  : containerH / imgH;
          final renderedW = imgW * scale;
          final renderedH = imgH * scale;
          final offsetX = (containerW - renderedW) / 2;
          final offsetY = (containerH - renderedH) / 2;

          return Stack(
            children: [
              // Base image layer
              Positioned.fill(
                child: Image.file(
                  File(imagePath),
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, error, _) => Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.broken_image, size: 48),
                        const SizedBox(height: 8),
                        Text(
                          'Could not load image',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Word tap targets
              if (widget.page.blocks.isNotEmpty)
                MangaWordOverlay(
                  blocks: widget.page.blocks,
                  scale: scale,
                  offsetX: offsetX,
                  offsetY: offsetY,
                  debugMode: widget.debugOverlay,
                  onWordTapped: widget.onWordTapped,
                ),

              // Highlighted word bounding box (single word selection indicator)
              if (widget.highlightedWord != null)
                _buildWordHighlight(
                  widget.highlightedWord!,
                  scale,
                  offsetX,
                  offsetY,
                ),
            ],
          );
        },
      ),
    );
  }

  /// Renders a highlight box around a single word, similar to the debug
  /// overlay but with a distinctive selection color.
  Widget _buildWordHighlight(
    MokuroWord word,
    double scale,
    double offsetX,
    double offsetY,
  ) {
    final bbox = word.boundingBox;
    final left = bbox.left * scale + offsetX;
    final top = bbox.top * scale + offsetY;
    final width = bbox.width * scale;
    final height = bbox.height * scale;

    if (width <= 0 || height <= 0) return const SizedBox.shrink();

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: Colors.cyan,
              width: 2,
            ),
            color: Colors.cyan.withAlpha(30),
          ),
        ),
      ),
    );
  }
}
