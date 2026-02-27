import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/library/presentation/providers/library_providers.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/presentation/widgets/manga_page_view.dart';

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
  void scrollToPage(int page) {
    if (!_scrollController.hasClients) return;
    final totalPages = widget.mokuroBook.pages.length;
    final clamped = page.clamp(0, totalPages - 1);

    // Estimate offset: each page occupies roughly one viewport height,
    // adjusted by aspect ratio. For simplicity use viewport height as
    // the baseline per-item height (since each page is full-width with
    // an AspectRatio wrapper, actual heights vary).
    final viewportHeight = _scrollController.position.viewportDimension;
    final targetOffset = clamped * viewportHeight;
    _scrollController.animateTo(
      targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
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
    final offset = _scrollController.offset;
    final viewportHeight = _scrollController.position.viewportDimension;
    // Use the center of the viewport to determine "current" page
    final centerOffset = offset + viewportHeight / 2;
    return (centerOffset / viewportHeight).floor().clamp(
      0,
      widget.mokuroBook.pages.length - 1,
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
        final aspectRatio = page.imgWidth > 0 && page.imgHeight > 0
            ? page.imgWidth / page.imgHeight
            : 0.7; // fallback for corrupt dimensions

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
