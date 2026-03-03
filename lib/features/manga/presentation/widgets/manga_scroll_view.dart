import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/library/presentation/providers/library_providers.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/presentation/widgets/manga_page_view.dart';

double resolveScrollPageAspectRatio(MokuroPage page, {required bool autoCrop}) {
  final contentBounds = autoCrop ? page.contentBounds : null;
  final width = contentBounds?.width ?? page.imgWidth.toDouble();
  final height = contentBounds?.height ?? page.imgHeight.toDouble();
  if (width <= 0 || height <= 0) {
    return 0.7; // fallback for corrupt dimensions
  }
  return width / height;
}

/// Continuous vertical scroll view for manga pages.
///
/// Each page is rendered at full width with its natural aspect ratio.
/// A debounced timer saves reading progress as `'scroll:<offset>'` in the
/// book's `lastReadCfi` field. The estimated current page is reported via
/// [onPageEstimateChanged] for the parent's slider/indicator.
class MangaScrollView extends ConsumerStatefulWidget {
  final MokuroBook mokuroBook;
  final int bookId;
  final double initialScrollOffset;
  final int initialPage;
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
  final ValueChanged<int>? onPageEstimateChanged;

  const MangaScrollView({
    super.key,
    required this.mokuroBook,
    required this.bookId,
    this.initialScrollOffset = 0.0,
    this.initialPage = 0,
    this.debugOverlay = false,
    this.autoCrop = false,
    this.enableWordOverlays = true,
    this.highlightedWord,
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
  bool _restoredInitialPage = false;
  int _restoreAttempts = 0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(
      initialScrollOffset: widget.initialScrollOffset,
    );
    _scrollController.addListener(_onScroll);

    if (widget.initialScrollOffset <= 0 && widget.initialPage > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _restoreInitialPageIfReady();
      });
    }
  }

  void _restoreInitialPageIfReady() {
    if (!mounted || _restoredInitialPage) return;

    final hasViewport =
        _scrollController.hasClients &&
        _scrollController.position.hasViewportDimension;
    if (hasViewport) {
      _restoredInitialPage = true;
      jumpToPage(widget.initialPage);
      return;
    }

    if (_restoreAttempts >= 8) return;
    _restoreAttempts++;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreInitialPageIfReady();
    });
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// Scroll so that the given [page] is visible at the top of the viewport.
  void scrollToPage(int page) {
    if (!_scrollController.hasClients) return;
    final totalPages = widget.mokuroBook.pages.length;
    final clamped = page.clamp(0, totalPages - 1);
    final targetOffset = _targetOffsetForPage(clamped);
    _scrollController.animateTo(
      targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  /// Jump to page without animation (used for initial mode switches).
  void jumpToPage(int page) {
    if (!_scrollController.hasClients) return;
    final totalPages = widget.mokuroBook.pages.length;
    final clamped = page.clamp(0, totalPages - 1);
    final targetOffset = _targetOffsetForPage(clamped);
    _scrollController.jumpTo(
      targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
    );
  }

  double _targetOffsetForPage(int page) {
    final viewportWidth = MediaQuery.sizeOf(context).width;
    if (viewportWidth <= 0 || page <= 0) return 0;
    double offset = 0;
    for (int i = 0; i < page && i < widget.mokuroBook.pages.length; i++) {
      final ratio = resolveScrollPageAspectRatio(
        widget.mokuroBook.pages[i],
        autoCrop: widget.autoCrop,
      );
      final safeRatio = ratio <= 0 ? 0.7 : ratio;
      offset += viewportWidth / safeRatio;
    }
    return offset;
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
    final viewportWidth = MediaQuery.sizeOf(context).width;
    if (viewportWidth <= 0) return 0;

    final centerOffset =
        _scrollController.offset +
        _scrollController.position.viewportDimension / 2;

    double running = 0;
    for (int i = 0; i < widget.mokuroBook.pages.length; i++) {
      final ratio = resolveScrollPageAspectRatio(
        widget.mokuroBook.pages[i],
        autoCrop: widget.autoCrop,
      );
      final safeRatio = ratio <= 0 ? 0.7 : ratio;
      running += viewportWidth / safeRatio;
      if (centerOffset < running) {
        return i;
      }
    }
    return widget.mokuroBook.pages.length - 1;
  }

  @override
  Widget build(BuildContext context) {
    final pages = widget.mokuroBook.pages;

    return ListView.builder(
      controller: _scrollController,
      itemCount: pages.length,
      itemBuilder: (context, index) {
        final page = pages[index];
        final aspectRatio = resolveScrollPageAspectRatio(
          page,
          autoCrop: widget.autoCrop,
        );

        return AspectRatio(
          aspectRatio: aspectRatio,
          child: MangaPageView(
            page: page,
            imageDirPath: widget.mokuroBook.imageDirPath,
            safTreeUri: widget.mokuroBook.safTreeUri,
            safImageDirRelativePath: widget.mokuroBook.safImageDirRelativePath,
            debugOverlay: widget.debugOverlay,
            autoCrop: widget.autoCrop,
            enableWordOverlays: widget.enableWordOverlays,
            highlightedWord: index == widget.highlightedPageIndex
                ? widget.highlightedWord
                : null,
            onWordTapped: widget.onWordTapped,
            // No onZoomChanged — scroll view doesn't block scrolling on zoom
          ),
        );
      },
    );
  }
}
