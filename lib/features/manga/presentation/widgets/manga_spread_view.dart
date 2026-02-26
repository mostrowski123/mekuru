import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/data/services/page_spread_calculator.dart';
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

    // Two pages side by side
    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          children: [
            Expanded(child: _buildPageContent(context, spread.leftPageIndex!)),
            Expanded(child: _buildPageContent(context, spread.rightPageIndex!)),
          ],
        );
      },
    );
  }

  /// Renders a single page's image and word overlay, scaled to fit its
  /// allocation (either full width for solo pages, or half-width in a spread).
  Widget _buildPageContent(BuildContext context, int pageIndex) {
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
        final contentBounds = page.contentBounds;
        final useCrop = widget.autoCrop && contentBounds != null;
        final regionW = useCrop ? contentBounds.width : imgW;
        final regionH = useCrop ? contentBounds.height : imgH;

        final scale = (containerW / regionW) < (containerH / regionH)
            ? containerW / regionW
            : containerH / regionH;

        final renderedRegionW = regionW * scale;
        final renderedRegionH = regionH * scale;
        final displayOffsetX = (containerW - renderedRegionW) / 2;
        final displayOffsetY = (containerH - renderedRegionH) / 2;

        final overlayOffsetX = useCrop
            ? displayOffsetX - contentBounds.left * scale
            : displayOffsetX;
        final overlayOffsetY = useCrop
            ? displayOffsetY - contentBounds.top * scale
            : displayOffsetY;

        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            // Image
            if (useCrop)
              Positioned(
                left: overlayOffsetX,
                top: overlayOffsetY,
                width: imgW * scale,
                height: imgH * scale,
                child: _buildPageImage(
                  imagePath,
                  safImageRelPath: safImageRelPath,
                  fit: BoxFit.fill,
                ),
              )
            else
              Positioned.fill(
                child: _buildPageImage(
                  imagePath,
                  safImageRelPath: safImageRelPath,
                  fit: BoxFit.contain,
                ),
              ),

            // Word overlay
            if (page.blocks.isNotEmpty)
              MangaWordOverlay(
                blocks: page.blocks,
                scale: scale,
                offsetX: overlayOffsetX,
                offsetY: overlayOffsetY,
                debugMode: widget.debugOverlay,
                onWordTapped: widget.onWordTapped,
              ),

            // Highlighted word
            if (widget.highlightedWord != null &&
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
  }) {
    if (widget.mokuroBook.safTreeUri != null && safImageRelPath != null) {
      return AndroidSafImage(
        treeUri: widget.mokuroBook.safTreeUri,
        relativePath: safImageRelPath,
        fit: fit,
        filterQuality: FilterQuality.medium,
      );
    }

    return Image.file(
      File(imagePath),
      fit: fit,
      filterQuality: FilterQuality.medium,
    );
  }
}
