import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mekuru/core/platform/image_convert.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/data/services/page_spread_calculator.dart';
import 'package:mekuru/features/manga/presentation/utils/crop_display_geometry.dart';
import 'package:mekuru/features/manga/presentation/widgets/manga_word_highlight_overlay.dart';
import 'package:mekuru/features/manga/presentation/widgets/manga_word_overlay.dart';
import 'package:mekuru/features/manga/presentation/widgets/manga_zoom_viewer.dart';
import 'package:mekuru/shared/widgets/android_saf_image.dart';

/// A manga page's image decoded [cacheWidth] physical pixels wide, read from
/// the user's folder (SAF) or from a file.
ImageProvider mangaPageImage(MokuroBook book, MokuroPage page, int cacheWidth) {
  final safImagePath = book.safImagePathFor(page);
  return safImagePath != null
      ? ResizeImage(
          AndroidSafImageProvider(
            treeUri: book.safTreeUri,
            relativePath: safImagePath,
          ),
          width: cacheWidth,
        )
      : fileImage(
          File('${book.imageDirPath}/${page.imageFileName}'),
          cacheWidth: cacheWidth,
        );
}

/// The image [MangaSpreadView] shows [page] of [spread] with when the view is
/// [viewWidth] wide: a page of a pair fills half of it, a page that stands
/// alone all of it. The reader's background asks for this same image, so a
/// page turn decodes each page once.
ImageProvider spreadPageImage(
  BuildContext context,
  MokuroBook book,
  PageSpread spread,
  MokuroPage page,
  double viewWidth,
) => mangaPageImage(
  book,
  page,
  ((spread.isSinglePage ? viewWidth : viewWidth / 2) *
          MediaQuery.devicePixelRatioOf(context))
      .toInt(),
);

/// Two-page spread view for manga reading.
///
/// Renders pages in pairs using [PageSpread] data from [computeSpreads].
/// Both pages in a spread share one [MangaZoomViewer] so they zoom
/// together. Cover and trailing odd pages are displayed as single pages
/// centered in the viewport.
class MangaSpreadView extends StatefulWidget {
  final MokuroBook mokuroBook;
  final List<PageSpread> spreads;

  /// The spread holding the reader's page: shown first, and again whenever
  /// [spreads] change.
  final int initialSpreadIndex;
  final bool isRtl;

  /// When false (e-reader mode) swipes don't drag the spreads, and
  /// programmatic turns jump instantly.
  final bool animatePageTurns;
  final bool debugOverlay;
  final bool autoCrop;
  final bool enableWordOverlays;
  final List<Rect> highlightedRects;
  final int? highlightedPageIndex;
  final MangaWordTapCallback? onWordTapped;
  final ValueChanged<bool>? onZoomChanged;
  final ValueChanged<int>? onSpreadChanged;

  const MangaSpreadView({
    super.key,
    required this.mokuroBook,
    required this.spreads,
    this.initialSpreadIndex = 0,
    this.isRtl = true,
    this.animatePageTurns = true,
    this.debugOverlay = false,
    this.autoCrop = false,
    this.enableWordOverlays = true,
    this.highlightedRects = const [],
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

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialSpreadIndex);
  }

  /// New pairs (detection, shift or direction changed) keep the page that
  /// was on screen: [MangaSpreadView.initialSpreadIndex] is its spread.
  @override
  void didUpdateWidget(MangaSpreadView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (listEquals(oldWidget.spreads, widget.spreads)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pageController.hasClients) {
        goToSpread(widget.initialSpreadIndex, animate: false);
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void goToSpread(int spreadIndex, {bool animate = true}) {
    final clamped = spreadIndex.clamp(0, widget.spreads.length - 1);
    if (!animate) {
      _pageController.jumpToPage(clamped);
      return;
    }
    _pageController.animateToPage(
      clamped,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: _pageController,
      reverse: widget.isRtl,
      // Keep the adjacent spreads built and decoded so instant
      // (no-animation) jumps have pixels ready on the jump frame.
      allowImplicitScrolling: true,
      // Swipes come through each spread's MangaZoomViewer, so the
      // PageView's own drag can't race pinch-zoom. The Clamping parent
      // stops those drags at the first and last spread.
      physics: const NeverScrollableScrollPhysics(
        parent: ClampingScrollPhysics(),
      ),
      itemCount: widget.spreads.length,
      onPageChanged: widget.onSpreadChanged,
      itemBuilder: (context, spreadIdx) {
        final spread = widget.spreads[spreadIdx];
        return MangaZoomViewer(
          pageIndex: spreadIdx,
          pageController: _pageController,
          animatePageTurns: widget.animatePageTurns,
          onZoomChanged: widget.onZoomChanged,
          child: _buildSpread(context, spread),
        );
      },
    );
  }

  Widget _buildSpread(BuildContext context, PageSpread spread) {
    if (spread.isSinglePage) {
      // Single page centered — cover or trailing odd page
      return LayoutBuilder(
        builder: (context, constraints) => Center(
          child: _buildPageContent(
            context,
            spread,
            spread.primaryPageIndex,
            constraints.maxWidth,
          ),
        ),
      );
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
                spread,
                spread.leftPageIndex!,
                constraints.maxWidth,
                cropBoundsOverride: sharedCropBounds.$1,
                scaleOverride: sharedScale,
              ),
            ),
            Expanded(
              child: _buildPageContent(
                context,
                spread,
                spread.rightPageIndex!,
                constraints.maxWidth,
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
  /// allocation (either full width for solo pages, or half-width in a spread)
  /// in a view [viewWidth] wide.
  Widget _buildPageContent(
    BuildContext context,
    PageSpread spread,
    int pageIndex,
    double viewWidth, {
    Rect? cropBoundsOverride,
    double? scaleOverride,
  }) {
    final pages = widget.mokuroBook.pages;
    if (pageIndex < 0 || pageIndex >= pages.length) {
      return const SizedBox.shrink();
    }

    final page = pages[pageIndex];
    final imgW = page.imgWidth.toDouble();
    final imgH = page.imgHeight.toDouble();

    if (imgW == 0 || imgH == 0) {
      return const Center(child: Icon(Icons.broken_image, size: 48));
    }
    final image = spreadPageImage(
      context,
      widget.mokuroBook,
      spread,
      page,
      viewWidth,
    );

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
                        child: _buildPageImage(page, image, BoxFit.fill),
                      ),
                    ),
                  ),
                ),
              )
            else
              Positioned.fill(
                child: _buildPageImage(page, image, BoxFit.contain),
              ),

            // Word overlay (hidden during active OCR)
            if (widget.enableWordOverlays && page.blocks.isNotEmpty)
              MangaWordOverlay(
                pageIndex: pageIndex,
                blocks: page.blocks,
                scale: scale,
                offsetX: overlayOffsetX,
                offsetY: overlayOffsetY,
                debugMode: widget.debugOverlay,
                onWordTapped: widget.onWordTapped,
              ),

            // Highlighted word rect(s) for the active lookup
            if (widget.enableWordOverlays &&
                widget.highlightedRects.isNotEmpty &&
                widget.highlightedPageIndex == pageIndex)
              MangaWordHighlightOverlay(
                rects: widget.highlightedRects,
                scale: scale,
                offsetX: overlayOffsetX,
                offsetY: overlayOffsetY,
              ),
          ],
        );
      },
    );
  }

  Widget _buildPageImage(MokuroPage page, ImageProvider image, BoxFit fit) =>
      Image(
        image: image,
        fit: fit,
        filterQuality: FilterQuality.medium,
        // As AndroidSafImage: a page the user's folder does not give shows
        // nothing.
        errorBuilder: widget.mokuroBook.safImagePathFor(page) == null
            ? null
            : (_, _, _) => const SizedBox.shrink(),
      );
}
