import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/library/presentation/providers/library_providers.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/presentation/widgets/manga_page_view.dart';
import 'package:mekuru/features/manga/presentation/widgets/manga_word_overlay.dart';

double _aspectRatio(MokuroPage page) => page.imgWidth > 0 && page.imgHeight > 0
    ? page.imgWidth / page.imgHeight
    : 0.7; // fallback for corrupt dimensions

/// Where each page starts in [MangaScrollView], which lays pages out at
/// [width] and their own aspect ratio. One entry longer than [pages]: the
/// last is where the final page ends.
List<double> mangaScrollPageTops(List<MokuroPage> pages, double width) {
  final tops = [0.0];
  for (final page in pages) {
    tops.add(tops.last + width / _aspectRatio(page));
  }
  return tops;
}

/// The page at the middle of the screen, or the last page once the view
/// can't scroll further, so that the end of a book reads as its last page.
int mangaScrollPageAt(
  List<double> pageTops, {
  required double offset,
  required double viewport,
}) {
  final lastPage = pageTops.length - 2;
  if (offset >= pageTops.last - viewport - 0.5) return lastPage;
  final middle = offset + viewport / 2;
  var page = 0;
  while (page < lastPage && pageTops[page + 1] <= middle) {
    page++;
  }
  return page;
}

/// Continuous vertical scroll view for manga pages.
///
/// Each page is rendered at full width with its natural aspect ratio.
/// A debounced timer saves reading progress as `'scroll:<offset>'` in the
/// book's `lastReadCfi` field. The current page (see [mangaScrollPageAt]) is
/// reported via [onPageEstimateChanged] for the parent's slider/indicator.
class MangaScrollView extends ConsumerStatefulWidget {
  final MokuroBook mokuroBook;
  final int bookId;
  final double initialScrollOffset;
  final bool debugOverlay;
  final bool autoCrop;
  final bool enableWordOverlays;
  final List<Rect> highlightedRects;
  final int? highlightedPageIndex;
  final MangaWordTapCallback? onWordTapped;
  final ValueChanged<int>? onPageEstimateChanged;

  const MangaScrollView({
    super.key,
    required this.mokuroBook,
    required this.bookId,
    this.initialScrollOffset = 0.0,
    this.debugOverlay = false,
    this.autoCrop = false,
    this.enableWordOverlays = true,
    this.highlightedRects = const [],
    this.highlightedPageIndex,
    this.onWordTapped,
    this.onPageEstimateChanged,
  });

  @override
  ConsumerState<MangaScrollView> createState() => MangaScrollViewState();
}

class MangaScrollViewState extends ConsumerState<MangaScrollView> {
  late final ScrollController _scrollController;
  Timer? _saveDebounce;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(
      initialScrollOffset: widget.initialScrollOffset,
    );
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// Scroll so that the given [page] is visible at the top of the viewport.
  void scrollToPage(int page, {bool animate = true}) {
    if (!_scrollController.hasClients) return;
    final clamped = page.clamp(0, widget.mokuroBook.pages.length - 1);
    _scrollTo(_pageTops()[clamped], animate: animate);
  }

  List<double> _pageTops() =>
      mangaScrollPageTops(widget.mokuroBook.pages, context.size!.width);

  /// Scrolls [screens] screens down (negative: up), which is what the page
  /// keys and volume buttons do here, as in the EPUB reader's scroll view.
  void scrollByScreens(int screens, {bool animate = true}) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    _scrollTo(
      position.pixels + screens * position.viewportDimension,
      animate: animate,
    );
  }

  void _scrollTo(double offset, {required bool animate}) {
    final clampedOffset = offset.clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    if (!animate) {
      _scrollController.jumpTo(clampedOffset);
      return;
    }
    _scrollController.animateTo(
      clampedOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _onScroll() {
    final page = _estimateCurrentPage();
    widget.onPageEstimateChanged?.call(page);

    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      final totalPages = widget.mokuroBook.pages.length;
      final progress = totalPages > 1 ? page / (totalPages - 1) : 0.0;
      ref
          .read(bookRepositoryProvider)
          .updateProgress(
            widget.bookId,
            'scroll:${_scrollController.offset}',
            progress: progress,
          );
    });
  }

  int _estimateCurrentPage() {
    if (!_scrollController.hasClients) return 0;
    return mangaScrollPageAt(
      _pageTops(),
      offset: _scrollController.offset,
      viewport: _scrollController.position.viewportDimension,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = widget.mokuroBook.pages;

    return ListView.builder(
      controller: _scrollController,
      itemCount: pages.length,
      itemBuilder: (context, index) {
        final page = pages[index];
        return AspectRatio(
          aspectRatio: _aspectRatio(page),
          child: MangaPageView(
            pageIndex: index,
            page: page,
            imageDirPath: widget.mokuroBook.imageDirPath,
            safTreeUri: widget.mokuroBook.safTreeUri,
            safImageDirRelativePath: widget.mokuroBook.safImageDirRelativePath,
            debugOverlay: widget.debugOverlay,
            autoCrop: widget.autoCrop,
            enableWordOverlays: widget.enableWordOverlays,
            highlightedRects: widget.highlightedRects,
            highlightedPageIndex: widget.highlightedPageIndex,
            onWordTapped: widget.onWordTapped,
            // No onZoomChanged — scroll view doesn't block scrolling on zoom
          ),
        );
      },
    );
  }
}
