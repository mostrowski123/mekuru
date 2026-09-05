import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/library/presentation/providers/library_providers.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/data/services/ocr_background_worker.dart';
import 'package:mekuru/features/manga/presentation/providers/manga_reader_providers.dart';
import 'package:mekuru/features/manga/presentation/providers/pro_access_provider.dart';
import 'package:mekuru/features/manga/data/services/page_char_counter.dart';
import 'package:mekuru/features/manga/data/services/page_spread_calculator.dart';
import 'package:mekuru/features/manga/presentation/screens/pro_upgrade_screen.dart';
import 'package:mekuru/features/manga/presentation/widgets/manga_page_view.dart';
import 'package:mekuru/features/manga/presentation/widgets/manga_reader_settings_sheet.dart';
import 'package:mekuru/features/manga/presentation/widgets/manga_scroll_view.dart';
import 'package:mekuru/features/manga/presentation/widgets/manga_spread_view.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/data/reader_session_tracker.dart';
import 'package:mekuru/features/reader/data/services/mecab_service.dart';
import 'package:mekuru/features/manga/presentation/providers/ocr_progress_provider.dart';
import 'package:mekuru/features/reader/presentation/reader_interaction_logic.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/features/reader/presentation/widgets/lookup_sheet.dart';
import 'package:mekuru/features/reader/presentation/widgets/reader_settings/reader_settings_sheet_scaffold.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/features/settings/presentation/screens/reading_settings_screen.dart';
import 'package:mekuru/features/stats/data/repositories/stats_repository.dart';
import 'package:mekuru/features/stats/presentation/providers/stats_providers.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/features/sync/presentation/providers/sync_providers.dart';
import 'package:mekuru/shared/review/reading_session_review_prompt.dart';
import 'package:mekuru/shared/utils/haptics.dart';
import 'package:mekuru/shared/utils/reader_system_bars.dart';
import 'package:mekuru/shared/widgets/android_saf_image.dart';
import 'package:mekuru/shared/widgets/reader_seek_bar.dart';
import 'package:mekuru/shared/utils/app_routes.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Manga reader screen — renders manga pages with word overlays.
///
/// Takes a [Book] with `bookType == 'manga'`. Loads the cached page data
/// from `pages_cache.json` and displays images in a [PageView] with
/// interactive word tap targets for dictionary lookup.
///
/// Supports RTL (default) and LTR reading directions. Center tap toggles
/// controls; edge taps navigate pages. Pinch-to-zoom is handled by each
/// [MangaPageView] via [InteractiveViewer].
class MangaReaderScreen extends ConsumerStatefulWidget {
  final Book book;

  const MangaReaderScreen({super.key, required this.book});

  @override
  ConsumerState<MangaReaderScreen> createState() => _MangaReaderScreenState();
}

class _MangaReaderScreenState extends ConsumerState<MangaReaderScreen>
    with WidgetsBindingObserver, ReadingSessionReviewPrompt<MangaReaderScreen> {
  final ReaderSessionTracker _sessionTracker = ReaderSessionTracker(
    bookFormat: 'manga',
  );

  // Captured in initState: the session summary is emitted from dispose(),
  // where `ref` is already unusable.
  late final StatsRepository _statsRepository;
  late final ReaderBrightnessNotifier _brightnessNotifier;

  late PageController _pageController;
  int _currentPage = 0;
  bool _showControls = false;
  bool _isZoomed = false;
  bool _isComputingAutoCrop = false;
  bool _autoCropComputedThisSession = false;

  /// Set once the characters on the initially displayed page(s) have been
  /// counted, so rebuilds (and page-data reloads) don't count them again.
  bool _initialPageCharsCounted = false;

  /// Non-null while precaching is paused for a slider seek; see
  /// [_holdPrecacheDuringSeek].
  Timer? _seekPrecacheHoldTimer;

  bool get _seekPrecacheHold => _seekPrecacheHoldTimer != null;

  // View mode keys for cross-widget navigation
  final _scrollViewKey = GlobalKey<MangaScrollViewState>();
  final _spreadViewKey = GlobalKey<MangaSpreadViewState>();

  // Word highlight state — shown while a lookup sheet is active
  _WordHighlight? _highlight;
  int _lookupRequestId = 0;

  @override
  void initState() {
    super.initState();
    // Restore last read page from book's lastReadCfi.
    // Scroll mode stores offset as 'scroll:<offset>' — default to page 0.
    final cfi = widget.book.lastReadCfi ?? '';
    _currentPage = cfi.startsWith('scroll:') ? 0 : (int.tryParse(cfi) ?? 0);
    _pageController = PageController(initialPage: _currentPage);
    WidgetsBinding.instance.addObserver(this);
    logUsage('reader.book_opened', attrs: {'format': 'manga'});
    _statsRepository = ref.read(statsRepositoryProvider);
    // Captured here because dispose() calls it after `ref` is unusable.
    _brightnessNotifier = ref.read(readerBrightnessProvider.notifier);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // Idempotent — app startup usually hydrated these already.
      await ref.read(readerSettingsProvider.notifier).loadPersistedSettings();
      if (!mounted) return;
      if (ref.read(readerSettingsProvider).keepScreenOn) {
        WakelockPlus.enable();
      }
      unawaited(_brightnessNotifier.applyForReaderOpen());
      unawaited(_syncRemoteProgress());
    });

    unawaited(setReaderSystemBarsVisible(false));

    // Dismiss the library's "OCR Complete" overlay after the user opens
    // this manga once.
    unawaited(_acknowledgeCompletedOcrOverlay());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _emitSessionSummary(endReason: 'closed');
    _seekPrecacheHoldTimer?.cancel();
    _pageController.dispose();
    unawaited(_brightnessNotifier.resetBrightness());
    WakelockPlus.disable();
    unawaited(setReaderSystemBarsVisible(true));
    // Release cached manga page bitmaps so memory is reclaimed immediately
    // when returning to the library.
    PaintingBinding.instance.imageCache.clear();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _emitSessionSummary(endReason: 'backgrounded');
    } else if (state == AppLifecycleState.resumed) {
      _sessionTracker.resume();
    }
  }

  void _emitSessionSummary({required String endReason}) {
    final summary = _sessionTracker.takeSummary(endReason: endReason);
    if (summary == null) return;
    logUsage('session.summary', attrs: summary);
    durationUsage(
      'session.duration_ms',
      summary['duration_ms'] as int,
      attrs: {'format': 'manga'},
    );

    // Persist the session for the stats screen. Fire-and-forget: this also
    // runs from dispose(), where `ref` is already unusable — hence the
    // repository captured in initState.
    unawaited(
      _statsRepository.recordSessionSummary(
        summary: summary,
        bookId: widget.book.id,
      ),
    );
  }

  void _recordPageTurn({required bool forward}) {
    _sessionTracker.recordPageTurn();
    countUsage(
      'reader.page_turn',
      attrs: {'direction': forward ? 'forward' : 'backward', 'format': 'manga'},
    );
  }

  /// Pauses adjacent-page precaching while a slider seek is in flight: every
  /// page the seek animation sweeps past reports a page change, and
  /// precaching each would fire image reads for pages never shown. The timer
  /// is re-armed on every slider tick, so the hold outlives the last one by
  /// enough to cover its page-turn animation, then precaches around wherever
  /// the seek landed. (The swept pages' *characters* need no such gate — the
  /// session tracker's dwell requirement drops them.)
  void _holdPrecacheDuringSeek() {
    _seekPrecacheHoldTimer?.cancel();
    _seekPrecacheHoldTimer = Timer(const Duration(seconds: 1), () {
      _seekPrecacheHoldTimer = null;
      if (mounted) _precacheAdjacentPages();
    });
  }

  /// Reports the page(s) at [pageIndexes], which just became visible, to the
  /// session tracker as one keyed page — key '12' for a single page, '3+4'
  /// with the combined character count for a two-page spread. A spread must
  /// be a single call: the tracker holds only one pending page, so reporting
  /// its halves separately would evict the first before it could dwell. The
  /// key buys the same dwell gate the EPUB reader gets from its start CFI —
  /// see [ReaderSessionTracker.recordCharactersRead].
  ///
  /// Counting happens at display time, so a page shown before its OCR has
  /// finished contributes the characters it had then — zero for a page with no
  /// OCR text yet, permanently.
  void _recordPageCharacters(MokuroBook book, Iterable<int> pageIndexes) {
    final valid = pageIndexes
        .where((index) => index >= 0 && index < book.pages.length)
        .toList();
    if (valid.isEmpty) return;
    _sessionTracker.recordCharactersRead(
      valid.fold(0, (sum, index) => sum + charCountForPage(book.pages[index])),
      pageKey: valid.join('+'),
    );
  }

  /// The page indexes currently on screen.
  ///
  /// Two-page spread view shows both pages of the current spread. Single-page
  /// and scroll view show one: in scroll view that is the page at the viewport
  /// centre, so a page counts as displayed once it becomes the current page,
  /// even though neighbouring pages may be partly visible too.
  List<int> _visiblePageIndexes(
    MangaViewMode viewMode,
    List<PageSpread> spreads,
  ) {
    if (viewMode == MangaViewMode.twoPageSpread && spreads.isNotEmpty) {
      return _spreadPageIndexes(
        spreads[spreadIndexForPage(spreads, _currentPage)],
      );
    }
    return [_currentPage];
  }

  List<int> _spreadPageIndexes(PageSpread spread) => [
    if (spread.leftPageIndex != null) spread.leftPageIndex!,
    if (spread.rightPageIndex != null) spread.rightPageIndex!,
  ];

  /// Handles a settled page change. [displayedPages] lists every page index
  /// that just became visible — two in spread view; [page] alone by default.
  void _onPageChanged(
    int page,
    int totalPages,
    MokuroBook book, {
    List<int>? displayedPages,
  }) {
    if (page != _currentPage) {
      // Page-turn telemetry deliberately still counts seek sweeps; the
      // characters report is keyed, so the tracker's dwell gate drops them.
      _recordPageTurn(forward: page > _currentPage);
      _recordPageCharacters(book, displayedPages ?? [page]);
    }
    setState(() => _currentPage = page);

    // Save progress
    final progress = totalPages > 1 ? page / (totalPages - 1) : 0.0;
    ref
        .read(bookRepositoryProvider)
        .updateProgress(widget.book.id, page.toString(), progress: progress);

    _precacheAdjacentPages();
  }

  /// Precache the next few pages so they display instantly when swiped to.
  void _precacheAdjacentPages() {
    if (_seekPrecacheHold) return;

    // Spread pages decode at half-screen width, so full-width precache
    // entries would never be hit; the PageView's implicit scrolling already
    // preloads the adjacent spreads at the width they render at.
    final viewMode = ref.read(readerSettingsProvider).mangaViewMode;
    if (viewMode == MangaViewMode.twoPageSpread) return;

    final asyncBook = ref.read(mangaPagesProvider(widget.book.id));
    final mokuroBook = switch (asyncBook) {
      AsyncData<MokuroBook>(:final value) => value,
      _ => null,
    };
    if (mokuroBook == null || !mounted) return;

    // Forward pages first (the common reading direction), then one backward
    // so instant (no-animation) back-taps also have pixels ready. Kept small:
    // decoded pages are large relative to the image cache budget.
    const offsets = [1, 2, 3, -1];
    final screenWidth = MediaQuery.sizeOf(context).width;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = (screenWidth * dpr).toInt();

    for (final offset in offsets) {
      final idx = _currentPage + offset;
      if (idx < 0 || idx >= mokuroBook.pages.length) continue;

      final page = mokuroBook.pages[idx];
      final safImagePath = mokuroBook.safImagePathFor(page);
      final provider = safImagePath != null
          ? AndroidSafImageProvider(
              treeUri: mokuroBook.safTreeUri,
              relativePath: safImagePath,
            )
          : FileImage(File('${mokuroBook.imageDirPath}/${page.imageFileName}'))
                as ImageProvider;

      precacheImage(
        ResizeImage(provider, width: cacheWidth),
        context,
        onError: (_, _) {}, // missing/unreadable page images fail on display
      );
    }
  }

  Future<void> _acknowledgeCompletedOcrOverlay() async {
    final prefs = await SharedPreferences.getInstance();
    final progress = OcrProgress.load(prefs, widget.book.id);
    if (progress?.status == OcrStatus.completed) {
      await OcrProgress.clear(prefs, widget.book.id);
      if (mounted) {
        ref.invalidate(ocrProgressProvider(widget.book.id));
      }
    }
  }

  void _toggleControls() {
    _setControlsVisible(!_showControls);
  }

  void _setControlsVisible(bool visible) {
    if (_showControls == visible) return;
    setState(() => _showControls = visible);
    unawaited(setReaderSystemBarsVisible(visible));
  }

  /// Whether programmatic page turns animate (off for e-reader displays).
  bool get _animatePageTurns =>
      ref.read(readerSettingsProvider).mangaPageTurnAnimation;

  // E-reader mode swipe tracking. Raw pointer events instead of a gesture
  // recognizer: the page views' physics are disabled in this mode, and a
  // Listener can never steal pinch-zoom or word taps from the arena.
  Offset? _ereaderSwipeDownPosition;
  int _ereaderActivePointers = 0;
  bool _ereaderMultiTouch = false;

  void _onEreaderPointerDown(PointerDownEvent event) {
    _ereaderActivePointers += 1;
    if (_ereaderActivePointers > 1) {
      _ereaderMultiTouch = true;
      _ereaderSwipeDownPosition = null;
    } else {
      _ereaderMultiTouch = false;
      _ereaderSwipeDownPosition = event.position;
    }
  }

  void _onEreaderPointerCancel(PointerCancelEvent event) {
    if (_ereaderActivePointers > 0) _ereaderActivePointers -= 1;
    _ereaderSwipeDownPosition = null;
  }

  void _onEreaderPointerUp(
    PointerUpEvent event,
    MangaViewMode viewMode,
    ReaderDirection direction,
    int totalPages,
    List<PageSpread> spreads,
  ) {
    if (_ereaderActivePointers > 0) _ereaderActivePointers -= 1;
    final downPosition = _ereaderSwipeDownPosition;
    _ereaderSwipeDownPosition = null;
    if (downPosition == null ||
        _ereaderMultiTouch ||
        _ereaderActivePointers > 0 ||
        _isZoomed ||
        // Scroll mode keeps its native (direct-manipulation) scrolling.
        viewMode == MangaViewMode.scroll) {
      return;
    }

    final screenSize = MediaQuery.sizeOf(context);
    final intent = resolveEreaderSwipeIntent(
      downX: downPosition.dx,
      upX: event.position.dx,
      downY: downPosition.dy,
      upY: event.position.dy,
      screenWidth: screenSize.width,
      screenHeight: screenSize.height,
      readingDirection: direction,
    );
    switch (intent) {
      case ReaderNavigationIntent.goForward:
        _navigate(1, totalPages, spreads);
      case ReaderNavigationIntent.goBackward:
        _navigate(-1, totalPages, spreads);
      case ReaderNavigationIntent.toggleControls:
      case ReaderNavigationIntent.none:
        break;
    }
  }

  /// Pull server progress for a linked book; when the server is ahead,
  /// move there (the DB row was already updated by the sync service).
  Future<void> _syncRemoteProgress() async {
    final remote = await ref
        .read(progressSyncServiceProvider)
        .syncOnOpen(widget.book);
    var page = remote?.page;
    if (!mounted || page == null) return;
    // Kavita reports a completed chapter as pageNum == pages, one past the
    // last index; clamp like every other navigation path does.
    final total = widget.book.totalPages;
    if (total > 0) page = page.clamp(0, total - 1);
    if (page == _currentPage) return;
    if (_pageController.hasClients) {
      _pageController.jumpToPage(page);
    } else {
      // The PageView hasn't built yet (pages still loading) — swap in a
      // controller that starts at the remote page.
      final previous = _pageController;
      setState(() {
        _currentPage = page!;
        _pageController = PageController(initialPage: page);
      });
      previous.dispose();
    }
  }

  void _goToPage(int page, int totalPages) {
    final clamped = page.clamp(0, totalPages - 1);
    if (!_animatePageTurns) {
      _pageController.jumpToPage(clamped);
      return;
    }
    _pageController.animateToPage(
      clamped,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  /// Navigate forward or backward by [delta] pages/spreads depending on mode.
  void _navigate(int delta, int totalPages, List<PageSpread> spreads) {
    final viewMode = ref.read(readerSettingsProvider).mangaViewMode;
    switch (viewMode) {
      case MangaViewMode.singlePage:
        _goToPage(_currentPage + delta, totalPages);
      case MangaViewMode.twoPageSpread:
        if (spreads.isNotEmpty) {
          final si = spreadIndexForPage(spreads, _currentPage);
          _spreadViewKey.currentState?.goToSpread(
            si + delta,
            animate: _animatePageTurns,
          );
        }
      case MangaViewMode.scroll:
        _recordPageTurn(forward: delta > 0);
        _scrollViewKey.currentState?.scrollToPage(
          _currentPage + delta,
          animate: _animatePageTurns,
        );
    }
  }

  void _clearHighlight() {
    if (_highlight != null) {
      setState(() => _highlight = null);
    }
  }

  void _onWordTapped(
    int pageIndex,
    MokuroWord word,
    MokuroTextBlock block,
    Offset globalPosition,
  ) {
    // Determine top vs bottom positioning — if the word is in the bottom
    // half of the screen, show the sheet at the top to avoid covering it.
    final screenHeight = MediaQuery.of(context).size.height;
    final showAtTop = globalPosition.dy > screenHeight * 0.5;

    // Read transparency preference
    final transparent = ref.read(readerSettingsProvider).mangaTransparentLookup;

    // Instant feedback: highlight the tapped word's box. Refined to the
    // resolved word's span once the lookup completes.
    setState(() {
      _highlight = _WordHighlight(
        pageIndex: pageIndex,
        rects: [word.boundingBox],
      );
    });

    // Hide controls if visible
    if (_showControls) {
      _setControlsVisible(false);
    }

    final requestId = ++_lookupRequestId;
    unawaited(
      _openLookupSheet(
        pageIndex: pageIndex,
        word: word,
        block: block,
        showAtTop: showAtTop,
        transparent: transparent,
        requestId: requestId,
      ),
    );
  }

  Future<void> _openLookupSheet({
    required int pageIndex,
    required MokuroWord word,
    required MokuroTextBlock block,
    required bool showAtTop,
    required bool transparent,
    required int requestId,
  }) async {
    final resolved = await ref
        .read(mangaWordLookupResolverProvider)
        .resolve(word, block);
    if (!mounted || requestId != _lookupRequestId) return;
    final lookup = resolved.result;

    // Grow the highlight to cover the word that was actually looked up —
    // compound resolution can extend past (or start before) the tapped token.
    final highlight = _WordHighlight(
      pageIndex: pageIndex,
      rects: resolved.highlightRects,
    );
    final current = _highlight;
    if (current == null ||
        current.pageIndex != highlight.pageIndex ||
        !listEquals(current.rects, highlight.rects)) {
      setState(() => _highlight = highlight);
    }

    final restoredLookupTerm = await ref
        .read(mangaLookupOverrideStorageProvider)
        .loadOverride(
          bookId: widget.book.id,
          surfaceForm: lookup.surfaceForm,
          dictionaryForm: lookup.dictionaryForm,
        );
    if (!mounted || requestId != _lookupRequestId) return;

    final sheet = showAtTop
        ? _showTopSheet(highlight, lookup, transparent, restoredLookupTerm)
        : _showBottomSheet(highlight, lookup, transparent, restoredLookupTerm);
    await sheet;
    if (!mounted || requestId != _lookupRequestId) return;
    _clearHighlight();
  }

  void _recordLookupResolved(bool hit) {
    _sessionTracker.recordLookup(hit: hit);
    countUsage(
      'lookup.performed',
      attrs: {'source': 'ocr', 'result': hit ? 'hit' : 'miss'},
    );
  }

  Future<void> _saveLookupOverride(
    WordLookupResult lookup,
    String editedLookupTerm,
  ) async {
    final storage = ref.read(mangaLookupOverrideStorageProvider);
    final trimmedLookupTerm = editedLookupTerm.trim();
    if (trimmedLookupTerm.isEmpty) {
      return;
    }

    if (trimmedLookupTerm == lookup.dictionaryForm) {
      await storage.removeOverride(
        bookId: widget.book.id,
        surfaceForm: lookup.surfaceForm,
        dictionaryForm: lookup.dictionaryForm,
      );
      return;
    }

    await storage.saveOverride(
      bookId: widget.book.id,
      surfaceForm: lookup.surfaceForm,
      dictionaryForm: lookup.dictionaryForm,
      lookupTerm: trimmedLookupTerm,
    );
  }

  Future<void> _showBottomSheet(
    _WordHighlight highlight,
    WordLookupResult lookup,
    bool transparent,
    String? restoredLookupTerm,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: transparent ? Colors.transparent : null,
      barrierColor: transparent ? Colors.black.withAlpha(30) : null,
      builder: (_) => LookupSheet(
        selectedText: lookup.dictionaryForm,
        surfaceForm: lookup.surfaceForm,
        sentenceContext: lookup.sentenceContext,
        saveSource: 'manga',
        initialEditedText: restoredLookupTerm,
        editable: true,
        transparent: transparent,
        onTermSubmitted: (value) {
          unawaited(_saveLookupOverride(lookup, value));
        },
        onEditingStarted: () {
          setState(() => _highlight = highlight);
        },
        onEditingEnded: () {
          // Keep highlight while sheet is still open
        },
        onLookupResolved: _recordLookupResolved,
        onWordSaved: _sessionTracker.recordWordSaved,
      ),
    );
  }

  Future<void> _showTopSheet(
    _WordHighlight highlight,
    WordLookupResult lookup,
    bool transparent,
    String? restoredLookupTerm,
  ) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: context.l10n.readerDismiss,
      barrierColor: transparent ? Colors.black.withAlpha(30) : Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.topCenter,
          child: Material(
            color: Colors.transparent,
            child: LookupSheet(
              selectedText: lookup.dictionaryForm,
              surfaceForm: lookup.surfaceForm,
              sentenceContext: lookup.sentenceContext,
              saveSource: 'manga',
              initialEditedText: restoredLookupTerm,
              showAtTop: true,
              editable: true,
              transparent: transparent,
              onTermSubmitted: (value) {
                unawaited(_saveLookupOverride(lookup, value));
              },
              onEditingStarted: () {
                setState(() => _highlight = highlight);
              },
              onEditingEnded: () {
                // Keep highlight while sheet is still open
              },
              onLookupResolved: _recordLookupResolved,
              onWordSaved: _sessionTracker.recordWordSaved,
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
              .animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
          child: child,
        );
      },
    );
  }

  void _handleTap(
    TapUpDetails details,
    int totalPages, [
    List<PageSpread> spreads = const [],
  ]) {
    if (_isZoomed) return; // Don't navigate when zoomed

    final screenSize = MediaQuery.sizeOf(context);
    final normalizedX = (details.globalPosition.dx / screenSize.width)
        .clamp(0.0, 1.0)
        .toDouble();
    final normalizedY = (details.globalPosition.dy / screenSize.height)
        .clamp(0.0, 1.0)
        .toDouble();

    final readerSettings = ref.read(readerSettingsProvider);
    final readerDir = readerSettings.mangaReadingDirection;

    final intent = resolveTapIntent(
      normalizedX: normalizedX,
      normalizedY: normalizedY,
      readingDirection: readerDir,
      centerZoneWidthFraction: mangaCenterTapZoneWidthFromEdgeZoneWidth(
        readerSettings.mangaPageTurnEdgeZoneWidthFraction,
      ),
    );

    switch (intent) {
      case ReaderNavigationIntent.toggleControls:
        _toggleControls();
      case ReaderNavigationIntent.goForward:
        _navigate(1, totalPages, spreads);
      case ReaderNavigationIntent.goBackward:
        _navigate(-1, totalPages, spreads);
      case ReaderNavigationIntent.none:
        break;
    }
  }

  Future<void> _openProUpgradeFromReader() async {
    await openProUpgrade(context, ref, source: 'manga_reader');
  }

  void _showSettingsSheet(MokuroBook mokuroBook) {
    final hasComputedAutoCrop =
        mokuroBook.autoCropVersion > 0 ||
        mokuroBook.pages.any((page) => page.contentBounds != null);
    showReaderSettingsSheet(
      context: context,
      builder: (sheetContext) => MangaReaderSettingsSheet(
        hasComputedAutoCrop: hasComputedAutoCrop,
        onAutoCropToggled: (value) =>
            _handleAutoCropToggle(ref, mokuroBook, value),
        onAutoCropRerun: () => _handleAutoCropRerun(ref),
        onUnlockPro: _openProUpgradeFromReader,
        onSettingChanged: _recordSettingChanged,
        onOpenAllSettings: () {
          AppHaptics.light();
          Navigator.of(sheetContext).pop();
          unawaited(_openAllSettingsFromReader());
        },
      ),
    );
  }

  /// The manga reader hides the system bars; restore them for the settings
  /// screen and re-apply the reader state when returning.
  Future<void> _openAllSettingsFromReader() async {
    await setReaderSystemBarsVisible(true);
    if (!mounted) return;
    await Navigator.of(context).push(
      namedRoute('reading_settings', (_) => const ReadingSettingsScreen()),
    );
    if (!mounted) return;
    await setReaderSystemBarsVisible(_showControls);
  }

  void _recordSettingChanged(String setting, Object value) {
    _sessionTracker.recordSettingsChanged();
    logUsage(
      'reader.settings_changed',
      attrs: {'setting': setting, 'value': value, 'format': 'manga'},
    );
  }

  Future<void> _handleAutoCropToggle(
    WidgetRef ref,
    MokuroBook mokuroBook,
    bool enable,
  ) async {
    if (!proUnlockedValue(ref.read(proUnlockedProvider))) {
      await _openProUpgradeFromReader();
      return;
    }

    if (!enable) {
      ref.read(readerSettingsProvider.notifier).setMangaAutoCrop(false);
      return;
    }

    if (_isComputingAutoCrop) return;

    final latestAsyncBook = ref.read(mangaPagesProvider(widget.book.id));
    final latestLoadedBook = switch (latestAsyncBook) {
      AsyncData<MokuroBook>(:final value) => value,
      _ => null,
    };
    final bookForAutoCropCheck = latestLoadedBook ?? mokuroBook;
    final alreadyAutoCropped =
        _autoCropComputedThisSession ||
        bookForAutoCropCheck.autoCropVersion >=
            MokuroBook.currentAutoCropVersion;
    if (alreadyAutoCropped) {
      _autoCropComputedThisSession = true;
      ref.read(readerSettingsProvider.notifier).setMangaAutoCrop(true);
      return;
    }

    await _runAutoCropComputation(ref, force: false, enableAfterCompute: true);
  }

  Future<void> _handleAutoCropRerun(WidgetRef ref) {
    return _runAutoCropComputation(
      ref,
      force: true,
      enableAfterCompute: ref.read(readerSettingsProvider).mangaAutoCrop,
    );
  }

  Future<void> _runAutoCropComputation(
    WidgetRef ref, {
    required bool force,
    required bool enableAfterCompute,
  }) async {
    if (_isComputingAutoCrop) return;
    final l10n = context.l10n;
    final whiteThreshold = ref.read(autoCropWhiteThresholdProvider);

    final dialogTitle = force
        ? l10n.mangaAutoCropRerunDialogTitle
        : l10n.mangaAutoCropComputeTitle;
    final dialogBody = force
        ? l10n.mangaAutoCropRerunDialogBody
        : l10n.mangaAutoCropComputeBody;
    final progressBody = force
        ? l10n.mangaAutoCropRecomputingProgress
        : l10n.mangaAutoCropComputingProgress;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogTitle),
        content: Text(dialogBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.commonContinue),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    _isComputingAutoCrop = true;
    BuildContext? progressDialogContext;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (dialogContext) {
        progressDialogContext = dialogContext;
        return AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(progressBody)),
            ],
          ),
        );
      },
    );

    try {
      await ref
          .read(bookRepositoryProvider)
          .ensureMangaAutoCropComputed(
            widget.book,
            force: force,
            whiteThreshold: whiteThreshold,
          );
      _autoCropComputedThisSession = true;
      ref.invalidate(mangaPagesProvider(widget.book.id));
      ref
          .read(readerSettingsProvider.notifier)
          .setMangaAutoCrop(enableAfterCompute);
      if (force && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.mangaAutoCropBoundsRefreshed)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.mangaAutoCropSetupFailed(details: '$e'))),
        );
      }
    } finally {
      _isComputingAutoCrop = false;
      if (progressDialogContext != null && progressDialogContext!.mounted) {
        Navigator.of(progressDialogContext!).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pagesAsync = ref.watch(mangaPagesProvider(widget.book.id));
    // Select a record so unrelated settings churn (brightness, font size)
    // can't rebuild the whole reader behind an open settings sheet.
    final (viewMode, direction, mangaAutoCropEnabled, animatePageTurns) = ref
        .watch(
          readerSettingsProvider.select(
            (s) => (
              s.mangaViewMode,
              s.mangaReadingDirection,
              s.mangaAutoCrop,
              s.mangaPageTurnAnimation,
            ),
          ),
        );
    final isProUnlocked = proUnlockedValue(ref.watch(proUnlockedProvider));
    final autoCrop = isProUnlocked && mangaAutoCropEnabled;
    final isOcrRunning = ref.watch(isOcrRunningProvider(widget.book.id));
    final enableWordOverlays = !isOcrRunning;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: readerSystemBarsOverlayStyle,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: pagesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    context.l10n.mangaReaderFailedToLoad,
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    error.toString(),
                    style: const TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          data: (mokuroBook) {
            final totalPages = mokuroBook.pages.length;
            if (totalPages == 0) {
              return Center(
                child: Text(
                  context.l10n.mangaReaderNoPages,
                  style: const TextStyle(color: Colors.white),
                ),
              );
            }

            // Clamp restored page to valid range
            if (_currentPage >= totalPages) {
              _currentPage = totalPages - 1;
            }

            // Precache adjacent pages on first data load and after rebuilds.
            // precacheImage is a no-op for already-cached images.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _precacheAdjacentPages();
            });

            final isRtl = direction == ReaderDirection.rtl;
            final spreads = viewMode == MangaViewMode.twoPageSpread
                ? computeSpreads(totalPages, isRtl: isRtl)
                : <PageSpread>[];

            // Count the page(s) shown when the book first opens; every later
            // page is counted as it becomes visible. One-shot, because build
            // runs again on every setState and page-data re-emission.
            if (!_initialPageCharsCounted) {
              _initialPageCharsCounted = true;
              _recordPageCharacters(
                mokuroBook,
                _visiblePageIndexes(viewMode, spreads),
              );
            }

            return Stack(
              children: [
                // Page content with tap zones. In e-reader mode the page
                // views' swipe physics are disabled, so swipes are detected
                // from raw pointer events here (no gesture-arena entry that
                // could fight pinch-zoom) and turn pages instantly.
                Listener(
                  onPointerDown: animatePageTurns
                      ? null
                      : _onEreaderPointerDown,
                  onPointerCancel: animatePageTurns
                      ? null
                      : _onEreaderPointerCancel,
                  onPointerUp: animatePageTurns
                      ? null
                      : (event) => _onEreaderPointerUp(
                          event,
                          viewMode,
                          direction,
                          totalPages,
                          spreads,
                        ),
                  child: GestureDetector(
                    onTapUp: (details) =>
                        _handleTap(details, totalPages, spreads),
                    child: _buildViewContent(
                      mokuroBook,
                      viewMode,
                      spreads,
                      totalPages,
                      isRtl,
                      autoCrop,
                      enableWordOverlays,
                      animatePageTurns,
                    ),
                  ),
                ),

                // Top controls bar
                if (_showControls)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black87, Colors.transparent],
                        ),
                      ),
                      child: SafeArea(
                        bottom: false,
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.arrow_back,
                                color: Colors.white,
                              ),
                              onPressed: () => Navigator.pop(context),
                            ),
                            Expanded(
                              child: Text(
                                widget.book.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.settings,
                                color: Colors.white,
                              ),
                              onPressed: () => _showSettingsSheet(mokuroBook),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Bottom controls bar with page slider
                if (_showControls)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: ReaderSeekBar(
                      value: _currentPage.toDouble(),
                      isRtl: isRtl,
                      max: (totalPages - 1).toDouble(),
                      divisions: totalPages > 1 ? totalPages - 1 : null,
                      leadingLabel: (value) => '${value.round() + 1}',
                      trailingLabel: '$totalPages',
                      onChanged: (value) {
                        final page = value.round();
                        _holdPrecacheDuringSeek();
                        switch (viewMode) {
                          case MangaViewMode.singlePage:
                            _goToPage(page, totalPages);
                          case MangaViewMode.twoPageSpread:
                            final si = spreadIndexForPage(spreads, page);
                            _spreadViewKey.currentState?.goToSpread(
                              si,
                              animate: _animatePageTurns,
                            );
                          case MangaViewMode.scroll:
                            _scrollViewKey.currentState?.scrollToPage(
                              page,
                              animate: _animatePageTurns,
                            );
                        }
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Builds the main content area, switching between single-page,
  /// two-page spread, and continuous scroll based on [viewMode].
  Widget _buildViewContent(
    MokuroBook mokuroBook,
    MangaViewMode viewMode,
    List<PageSpread> spreads,
    int totalPages,
    bool isRtl,
    bool autoCrop,
    bool enableWordOverlays,
    bool animatePageTurns,
  ) {
    final debugOverlay = ref.watch(mangaDebugWordOverlayProvider);
    switch (viewMode) {
      case MangaViewMode.singlePage:
        // Sync page controller after a mode switch
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_pageController.hasClients &&
              (_pageController.page?.round() ?? 0) != _currentPage) {
            _pageController.jumpToPage(_currentPage);
          }
        });
        return PageView.builder(
          controller: _pageController,
          reverse: isRtl,
          // Keep the adjacent pages built and decoded so instant
          // (no-animation) jumps have pixels ready on the jump frame.
          allowImplicitScrolling: true,
          // E-reader mode: no swipe-drag at all — swipes are handled from
          // raw pointers in build() and jump instantly.
          physics: _isZoomed || !animatePageTurns
              ? const NeverScrollableScrollPhysics()
              : const ClampingScrollPhysics(),
          itemCount: totalPages,
          onPageChanged: (page) => _onPageChanged(page, totalPages, mokuroBook),
          itemBuilder: (context, index) {
            final page = mokuroBook.pages[index];
            return MangaPageView(
              pageIndex: index,
              page: page,
              imageDirPath: mokuroBook.imageDirPath,
              safTreeUri: mokuroBook.safTreeUri,
              safImageDirRelativePath: mokuroBook.safImageDirRelativePath,
              debugOverlay: debugOverlay,
              autoCrop: autoCrop,
              enableWordOverlays: enableWordOverlays,
              highlightedRects: _highlight?.rects ?? const [],
              highlightedPageIndex: _highlight?.pageIndex,
              onWordTapped: _onWordTapped,
              onZoomChanged: (zoomed) {
                if (zoomed != _isZoomed) {
                  setState(() => _isZoomed = zoomed);
                }
              },
            );
          },
        );

      case MangaViewMode.twoPageSpread:
        return MangaSpreadView(
          key: _spreadViewKey,
          mokuroBook: mokuroBook,
          spreads: spreads,
          initialSpreadIndex: spreadIndexForPage(spreads, _currentPage),
          isRtl: isRtl,
          animatePageTurns: animatePageTurns,
          debugOverlay: debugOverlay,
          autoCrop: autoCrop,
          enableWordOverlays: enableWordOverlays,
          highlightedRects: _highlight?.rects ?? const [],
          highlightedPageIndex: _highlight?.pageIndex,
          onWordTapped: _onWordTapped,
          onZoomChanged: (zoomed) {
            if (zoomed != _isZoomed) {
              setState(() => _isZoomed = zoomed);
            }
          },
          onSpreadChanged: (spreadIdx) {
            if (spreadIdx >= 0 && spreadIdx < spreads.length) {
              final spread = spreads[spreadIdx];
              _onPageChanged(
                spread.primaryPageIndex,
                totalPages,
                mokuroBook,
                displayedPages: _spreadPageIndexes(spread),
              );
            }
          },
        );

      case MangaViewMode.scroll:
        return MangaScrollView(
          key: _scrollViewKey,
          mokuroBook: mokuroBook,
          bookId: widget.book.id,
          initialScrollOffset:
              _currentPage * MediaQuery.of(context).size.height,
          debugOverlay: debugOverlay,
          autoCrop: autoCrop,
          enableWordOverlays: enableWordOverlays,
          highlightedRects: _highlight?.rects ?? const [],
          highlightedPageIndex: _highlight?.pageIndex,
          onWordTapped: _onWordTapped,
          onPageEstimateChanged: (page) {
            // Fires on every scroll tick, so report only when the page at
            // the viewport centre actually changes; pages a slider seek
            // scrolls past are dropped by the tracker's dwell gate.
            if (page != _currentPage) {
              _recordPageCharacters(mokuroBook, [page]);
            }
            setState(() => _currentPage = page);
            // Progress is saved by MangaScrollView's debounced callback
          },
        );
    }
  }
}

/// The lookup highlight currently drawn on a page: image-space rects plus
/// the index of the page they belong to.
class _WordHighlight {
  final int pageIndex;
  final List<Rect> rects;

  const _WordHighlight({required this.pageIndex, required this.rects});
}
