import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/data/services/page_spread_calculator.dart';
import 'package:mekuru/features/manga/presentation/utils/crop_display_geometry.dart';
import 'package:mekuru/features/manga/presentation/widgets/manga_word_overlay.dart';
import 'package:mekuru/shared/widgets/android_saf_image.dart';
import 'package:path/path.dart' as p;

/// Two-page spread view for manga reading.
///
/// Renders pages in pairs using [PageSpread] data from [computeSpreads].
/// Both pages in a spread share a single [InteractiveViewer] so they zoom
/// together. Cover and trailing odd pages are displayed as single pages
/// centered in the viewport.
class MangaSpreadView extends StatefulWidget {
  final MokuroBook mokuroBook;
  final List<PageSpread> spreads;
  final int initialSpreadIndex;
  final bool isRtl;
  final bool debugOverlay;
  final bool autoCrop;
  final bool enableWordOverlays;
  final MokuroWord? highlightedWord;
  final int? highlightedPageIndex;
  final void Function(
    MokuroWord word,
    MokuroTextBlock block,
    Offset globalPosition,
  )?
  onWordTapped;
  final ValueChanged<bool>? onZoomChanged;
  final ValueChanged<int>? onSpreadChanged;

  const MangaSpreadView({
    super.key,
    required this.mokuroBook,
    required this.spreads,
    this.initialSpreadIndex = 0,
    this.isRtl = true,
    this.debugOverlay = false,
    this.autoCrop = false,
    this.enableWordOverlays = true,
    this.highlightedWord,
    this.highlightedPageIndex,
    this.onWordTapped,
    this.onZoomChanged,
    this.onSpreadChanged,
  });

  @override
  State<MangaSpreadView> createState() => MangaSpreadViewState();
}

class MangaSpreadViewState extends State<MangaSpreadView> {
  late PageController _pageController;
  late TransformationController _transformController;
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialSpreadIndex);
    _transformController = TransformationController();
    _transformController.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _transformController.removeListener(_onTransformChanged);
    _transformController.dispose();
    super.dispose();
  }

  void goToSpread(int spreadIndex) {
    final clamped = spreadIndex.clamp(0, widget.spreads.length - 1);
    _pageController.animateToPage(
      clamped,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _onTransformChanged() {
    final scale = _transformController.value.getMaxScaleOnAxis();
    final zoomed = scale > 1.05;
    if (zoomed != _isZoomed) {
      _isZoomed = zoomed;
      widget.onZoomChanged?.call(zoomed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: _pageController,
      reverse: widget.isRtl,
      physics: _isZoomed
          ? const NeverScrollableScrollPhysics()
          : const ClampingScrollPhysics(),
      itemCount: widget.spreads.length,
      onPageChanged: (spreadIdx) {
        // Reset zoom when changing spreads
        if (_isZoomed) {
          _transformController.value = Matrix4.identity();
        }
        widget.onSpreadChanged?.call(spreadIdx);
      },
      itemBuilder: (context, spreadIdx) {
        final spread = widget.spreads[spreadIdx];
        return InteractiveViewer(
          transformationController: _transformController,
          minScale: 1.0,
          maxScale: 5.0,
          panEnabled: true,
          child: _buildSpread(context, spread),
        );
      },
    );
  }

  Widget _buildSpread(BuildContext context, PageSpread spread) {
    if (spread.isSinglePage) {
      // Single page centered — cover or trailing odd page
      final pageIdx = spread.primaryPageIndex;
      return Center(child: _buildPageContent(context, pageIdx));
    }

    final sharedCropBounds = _resolveSharedCropBounds(spread);

    // Two pages side by side
    return LayoutBuilder(
      builder: (context, constraints) {
        final halfWidth = constraints.maxWidth / 2;
        final maxHeight = constraints.maxHeight;

        // Compute a shared scale so both pages display at the same height.
        // _resolveSharedCropBounds ensures both crops have the same height
        // (assuming same image dimensions). Using the minimum scale of both
        // pages guarantees both fit within their half and display identically
        // tall with aligned tops and bottoms.
        double? sharedScale;
        if (widget.autoCrop &&
            sharedCropBounds.$1 != null &&
            sharedCropBounds.$2 != null) {
          sharedScale = computeSharedScale(
            leftCrop: sharedCropBounds.$1!,
            rightCrop: sharedCropBounds.$2!,
            halfWidth: halfWidth,
            maxHeight: maxHeight,
          );
        }

        return Row(
          children: [
            Expanded(
              child: _buildPageContent(
                context,
                spread.leftPageIndex!,
                cropBoundsOverride: sharedCropBounds.$1,
                scaleOverride: sharedScale,
              ),
            ),
            Expanded(
              child: _buildPageContent(
                context,
                spread.rightPageIndex!,
                cropBoundsOverride: sharedCropBounds.$2,
                scaleOverride: sharedScale,
              ),
            ),
          ],
        );
      },
    );
  }

  (Rect?, Rect?) _resolveSharedCropBounds(PageSpread spread) {
    if (!widget.autoCrop) return (null, null);

    final pages = widget.mokuroBook.pages;
    final leftIndex = spread.leftPageIndex;
    final rightIndex = spread.rightPageIndex;
    if (leftIndex == null ||
        rightIndex == null ||
        leftIndex < 0 ||
        rightIndex < 0 ||
        leftIndex >= pages.length ||
        rightIndex >= pages.length) {
      return (null, null);
    }

    final leftPage = pages[leftIndex];
    final rightPage = pages[rightIndex];

    return computeSharedCropBounds(
      leftContentBounds: leftPage.contentBounds,
      rightContentBounds: rightPage.contentBounds,
      leftImgW: leftPage.imgWidth.toDouble(),
      leftImgH: leftPage.imgHeight.toDouble(),
      rightImgW: rightPage.imgWidth.toDouble(),
      rightImgH: rightPage.imgHeight.toDouble(),
    );
  }

  /// Renders a single page's image and word overlay, scaled to fit its
  /// allocation (either full width for solo pages, or half-width in a spread).
  Widget _buildPageContent(
    BuildContext context,
    int pageIndex, {
    Rect? cropBoundsOverride,
    double? scaleOverride,
  }) {
    final pages = widget.mokuroBook.pages;
    if (pageIndex < 0 || pageIndex >= pages.length) {
      return const SizedBox.shrink();
    }

    final page = pages[pageIndex];
    final imagePath = '${widget.mokuroBook.imageDirPath}/${page.imageFileName}';
    final safImageRelPath =
        widget.mokuroBook.safTreeUri != null &&
            widget.mokuroBook.safImageDirRelativePath != null
        ? p.posix.join(
            widget.mokuroBook.safImageDirRelativePath!,
            page.imageFileName,
          )
        : null;
    final imgW = page.imgWidth.toDouble();
    final imgH = page.imgHeight.toDouble();

    if (imgW == 0 || imgH == 0) {
      return const Center(child: Icon(Icons.broken_image, size: 48));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final containerW = constraints.maxWidth;
        final containerH = constraints.maxHeight;

        // Auto-crop region
        final contentBounds = cropBoundsOverride ?? page.contentBounds;
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
            scaleOverride: scaleOverride,
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
          final regionW = imgW;
          final regionH = imgH;
          final baseScale = (containerW / regionW) < (containerH / regionH)
              ? containerW / regionW
              : containerH / regionH;
          scale = scaleOverride ?? baseScale;
          renderedRegionW = regionW * scale;
          renderedRegionH = regionH * scale;
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
            // Image — clipped to show only the content region
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
                        child: _buildPageImage(
                          imagePath,
                          safImageRelPath: safImageRelPath,
                          fit: BoxFit.fill,
                          cacheWidth: decodeCacheWidth,
                        ),
                      ),
                    ),
                  ),
                ),
              )
            else
              Positioned.fill(
                child: _buildPageImage(
                  imagePath,
                  safImageRelPath: safImageRelPath,
                  fit: BoxFit.contain,
                  cacheWidth: decodeCacheWidth,
                ),
              ),

            // Word overlay (hidden during active OCR)
            if (widget.enableWordOverlays && page.blocks.isNotEmpty)
              MangaWordOverlay(
                blocks: page.blocks,
                scale: scale,
                offsetX: overlayOffsetX,
                offsetY: overlayOffsetY,
                debugMode: widget.debugOverlay,
                onWordTapped: widget.onWordTapped,
              ),

            // Highlighted word
            if (widget.enableWordOverlays &&
                widget.highlightedWord != null &&
                widget.highlightedPageIndex == pageIndex)
              _buildWordHighlight(
                widget.highlightedWord!,
                scale,
                overlayOffsetX,
                overlayOffsetY,
              ),
          ],
        );
      },
    );
  }

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

  Widget _buildPageImage(
    String imagePath, {
    required String? safImageRelPath,
    required BoxFit fit,
    int? cacheWidth,
  }) {
    if (widget.mokuroBook.safTreeUri != null && safImageRelPath != null) {
      return AndroidSafImage(
        treeUri: widget.mokuroBook.safTreeUri,
        relativePath: safImageRelPath,
        fit: fit,
        cacheWidth: cacheWidth,
        filterQuality: FilterQuality.medium,
      );
    }

    return Image.file(
      File(imagePath),
      fit: fit,
      cacheWidth: cacheWidth,
      filterQuality: FilterQuality.medium,
    );
  }
}
