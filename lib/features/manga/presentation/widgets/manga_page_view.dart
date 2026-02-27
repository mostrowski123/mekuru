import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/presentation/widgets/manga_word_overlay.dart';
import 'package:mekuru/shared/widgets/android_saf_image.dart';
import 'package:path/path.dart' as p;

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
  final String? safTreeUri;
  final String? safImageDirRelativePath;
  final bool debugOverlay;
  final bool autoCrop;
  final bool enableWordOverlays;
  final MokuroWord? highlightedWord;
  final void Function(
    MokuroWord word,
    MokuroTextBlock block,
    Offset globalPosition,
  )?
  onWordTapped;
  final ValueChanged<bool>? onZoomChanged;

  const MangaPageView({
    super.key,
    required this.page,
    required this.imageDirPath,
    this.safTreeUri,
    this.safImageDirRelativePath,
    this.debugOverlay = false,
    this.autoCrop = false,
    this.enableWordOverlays = true,
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
    final imagePath = '${widget.imageDirPath}/${widget.page.imageFileName}';
    final safImageRelPath =
        widget.safTreeUri != null && widget.safImageDirRelativePath != null
        ? p.posix.join(
            widget.safImageDirRelativePath!,
            widget.page.imageFileName,
          )
        : null;

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
          if (imgW == 0 || imgH == 0) {
            return const Center(child: Icon(Icons.broken_image, size: 48));
          }

          // Determine effective region to display.
          // With auto-crop, we fit the contentBounds region to the container
          // instead of the full image, then translate the image so that
          // region is centered.
          final contentBounds = widget.page.contentBounds;
          final useCrop = widget.autoCrop && contentBounds != null;

          final double regionW = useCrop ? contentBounds.width : imgW;
          final double regionH = useCrop ? contentBounds.height : imgH;

          // Scale to fit the visible region into the container
          final scale = (containerW / regionW) < (containerH / regionH)
              ? containerW / regionW
              : containerH / regionH;

          final renderedRegionW = regionW * scale;
          final renderedRegionH = regionH * scale;
          final displayOffsetX = (containerW - renderedRegionW) / 2;
          final displayOffsetY = (containerH - renderedRegionH) / 2;

          // Overlay coordinates: map image-pixel coords → screen coords.
          // overlayX = (imgPixelX * scale) + overlayOffsetX
          // For full image: overlayOffsetX = displayOffsetX
          // For crop: overlayOffsetX = displayOffsetX - contentBounds.left * scale
          final overlayOffsetX = useCrop
              ? displayOffsetX - contentBounds.left * scale
              : displayOffsetX;
          final overlayOffsetY = useCrop
              ? displayOffsetY - contentBounds.top * scale
              : displayOffsetY;

          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              // Base image layer — positioned/scaled to show the target region
              if (useCrop)
                Positioned(
                  left: overlayOffsetX,
                  top: overlayOffsetY,
                  width: imgW * scale,
                  height: imgH * scale,
                  child: _buildImage(
                    imagePath,
                    safImageRelPath: safImageRelPath,
                  ),
                )
              else
                Positioned.fill(
                  child: _buildImage(
                    imagePath,
                    safImageRelPath: safImageRelPath,
                    fit: BoxFit.contain,
                  ),
                ),

              // Word tap targets (hidden during active OCR)
              if (widget.enableWordOverlays && widget.page.blocks.isNotEmpty)
                MangaWordOverlay(
                  blocks: widget.page.blocks,
                  scale: scale,
                  offsetX: overlayOffsetX,
                  offsetY: overlayOffsetY,
                  debugMode: widget.debugOverlay,
                  onWordTapped: widget.onWordTapped,
                ),

              // Highlighted word bounding box (single word selection indicator)
              if (widget.enableWordOverlays && widget.highlightedWord != null)
                _buildWordHighlight(
                  widget.highlightedWord!,
                  scale,
                  overlayOffsetX,
                  overlayOffsetY,
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildImage(
    String imagePath, {
    String? safImageRelPath,
    BoxFit fit = BoxFit.fill,
  }) {
    if (widget.safTreeUri != null && safImageRelPath != null) {
      return AndroidSafImage(
        treeUri: widget.safTreeUri,
        relativePath: safImageRelPath,
        fit: fit,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, error, _) => _buildImageError(context),
      );
    }

    return Image.file(
      File(imagePath),
      fit: fit,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, error, _) => _buildImageError(context),
    );
  }

  Widget _buildImageError(BuildContext context) {
    return Center(
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
            border: Border.all(color: Colors.cyan, width: 2),
            color: Colors.cyan.withAlpha(30),
          ),
        ),
      ),
    );
  }
}
