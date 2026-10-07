import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mekuru/core/platform/image_convert.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/presentation/utils/crop_display_geometry.dart';
import 'package:mekuru/features/manga/presentation/widgets/manga_word_highlight_overlay.dart';
import 'package:mekuru/features/manga/presentation/widgets/manga_word_overlay.dart';
import 'package:mekuru/features/manga/presentation/widgets/manga_zoom_viewer.dart';
import 'package:mekuru/shared/widgets/android_saf_image.dart';
import 'package:path/path.dart' as p;

/// Renders a single manga page image with pinch-to-zoom and word tap targets.
///
/// Uses [MangaZoomViewer] for zoom/pan and, given [pageController], swipe
/// page turns. A [LayoutBuilder] computes the `BoxFit.contain` scale and
/// offset so the [MangaWordOverlay] positions match the rendered image
/// exactly.
///
/// Reports zoom state changes via [onZoomChanged] so the reader can turn
/// off tap navigation while the user is zoomed in.
class MangaPageView extends StatefulWidget {
  final int pageIndex;
  final MokuroPage page;
  final String imageDirPath;
  final String? safTreeUri;
  final String? safImageDirRelativePath;
  final bool debugOverlay;
  final bool autoCrop;
  final bool enableWordOverlays;
  final List<Rect> highlightedRects;

  /// Page the [highlightedRects] belong to; they are drawn only when it
  /// matches [pageIndex].
  final int? highlightedPageIndex;
  final MangaWordTapCallback? onWordTapped;
  final ValueChanged<bool>? onZoomChanged;

  /// The surrounding [PageView]'s controller, for swipe page turns; null in
  /// scroll mode.
  final PageController? pageController;
  final bool animatePageTurns;

  const MangaPageView({
    super.key,
    required this.pageIndex,
    required this.page,
    required this.imageDirPath,
    this.safTreeUri,
    this.safImageDirRelativePath,
    this.debugOverlay = false,
    this.autoCrop = false,
    this.enableWordOverlays = true,
    this.highlightedRects = const [],
    this.highlightedPageIndex,
    this.onWordTapped,
    this.onZoomChanged,
    this.pageController,
    this.animatePageTurns = true,
  });

  @override
  State<MangaPageView> createState() => _MangaPageViewState();
}

class _MangaPageViewState extends State<MangaPageView> {
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

    return MangaZoomViewer(
      pageIndex: widget.pageIndex,
      pageController: widget.pageController,
      animatePageTurns: widget.animatePageTurns,
      onZoomChanged: widget.onZoomChanged,
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
          final contentBounds = widget.page.contentBounds;
          final useCrop = widget.autoCrop && contentBounds != null;

          final double scale;
          final double displayOffsetX, displayOffsetY;
          final double renderedRegionW, renderedRegionH;
          final double overlayOffsetX, overlayOffsetY;
          final double clipTranslateX, clipTranslateY;

          if (useCrop) {
            final geo = computeCropDisplayGeometry(
              containerW: containerW,
              containerH: containerH,
              imgW: imgW,
              imgH: imgH,
              contentBounds: contentBounds,
            );
            scale = geo.scale;
            displayOffsetX = geo.displayOffsetX;
            displayOffsetY = geo.displayOffsetY;
            renderedRegionW = geo.renderedRegionW;
            renderedRegionH = geo.renderedRegionH;
            overlayOffsetX = geo.overlayOffsetX;
            overlayOffsetY = geo.overlayOffsetY;
            clipTranslateX = geo.clipTranslateX;
            clipTranslateY = geo.clipTranslateY;
          } else {
            scale = math.min(containerW / imgW, containerH / imgH);
            renderedRegionW = imgW * scale;
            renderedRegionH = imgH * scale;
            displayOffsetX = (containerW - renderedRegionW) / 2;
            displayOffsetY = (containerH - renderedRegionH) / 2;
            overlayOffsetX = displayOffsetX;
            overlayOffsetY = displayOffsetY;
            clipTranslateX = 0;
            clipTranslateY = 0;
          }

          final decodeCacheWidth =
              (containerW * MediaQuery.devicePixelRatioOf(context)).toInt();

          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              // Base image layer — clipped to show only the content region
              if (useCrop)
                Positioned(
                  left: displayOffsetX,
                  top: displayOffsetY,
                  width: renderedRegionW,
                  height: renderedRegionH,
                  child: ClipRect(
                    child: OverflowBox(
                      maxWidth: imgW * scale,
                      maxHeight: imgH * scale,
                      alignment: Alignment.topLeft,
                      child: Transform.translate(
                        offset: Offset(clipTranslateX, clipTranslateY),
                        child: SizedBox(
                          width: imgW * scale,
                          height: imgH * scale,
                          child: _buildImage(
                            imagePath,
                            safImageRelPath: safImageRelPath,
                            cacheWidth: decodeCacheWidth,
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              else
                Positioned.fill(
                  child: _buildImage(
                    imagePath,
                    safImageRelPath: safImageRelPath,
                    fit: BoxFit.contain,
                    cacheWidth: decodeCacheWidth,
                  ),
                ),

              // Word tap targets (hidden during active OCR)
              if (widget.enableWordOverlays && widget.page.blocks.isNotEmpty)
                MangaWordOverlay(
                  pageIndex: widget.pageIndex,
                  blocks: widget.page.blocks,
                  scale: scale,
                  offsetX: overlayOffsetX,
                  offsetY: overlayOffsetY,
                  debugMode: widget.debugOverlay,
                  onWordTapped: widget.onWordTapped,
                ),

              // Highlighted word bounding box(es) for the active lookup
              if (widget.enableWordOverlays &&
                  widget.highlightedPageIndex == widget.pageIndex &&
                  widget.highlightedRects.isNotEmpty)
                MangaWordHighlightOverlay(
                  rects: widget.highlightedRects,
                  scale: scale,
                  offsetX: overlayOffsetX,
                  offsetY: overlayOffsetY,
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
    int? cacheWidth,
  }) {
    if (widget.safTreeUri != null && safImageRelPath != null) {
      return AndroidSafImage(
        treeUri: widget.safTreeUri,
        relativePath: safImageRelPath,
        fit: fit,
        cacheWidth: cacheWidth,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, error, _) => _buildImageError(context),
      );
    }

    return Image(
      image: fileImage(File(imagePath), cacheWidth: cacheWidth),
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
}
