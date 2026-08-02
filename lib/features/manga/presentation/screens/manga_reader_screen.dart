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
import 'package:mekuru/shared/review/reading_session_review_prompt.dart';
import 'package:mekuru/shared/utils/haptics.dart';
import 'package:mekuru/shared/utils/system_gesture_padding.dart';
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
const SystemUiOverlayStyle _mangaReaderOverlayStyle = SystemUiOverlayStyle(
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemNavigationBarIconBrightness: Brightness.light,
  systemStatusBarContrastEnforced: false,
  systemNavigationBarContrastEnforced: false,
);

class MangaReaderScreen extends ConsumerStatefulWidget {
  final Book book;

  const MangaReaderScreen({super.key, required this.book});

  @override
  ConsumerState<MangaReaderScreen> createState() => _MangaReaderScreenState();
}

class _MangaReaderScreenState extends ConsumerState<MangaReaderScreen>
    with WidgetsBindingObserver, ReadingSessionReviewPrompt<MangaReaderScreen> {
  static const _systemUiChannel = MethodChannel('mekuru/android_system_ui');

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

  /// Page the user is seeking to with the progress slider, while the seek is
  /// still in flight. Pages swept past on the way there are displayed, but
  /// were never read — see [_consumeSeekGate].
  int? _pendingSeekTarget;
  Timer? _seekGateTimeout;

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
    });

    unawaited(_setReaderSystemBarsVisible(false));

    // Dismiss the library's "OCR Complete" overlay after the user opens
    // this manga once.
    unawaited(_acknowledgeCompletedOcrOverlay());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _emitSessionSummary(endReason: 'closed');
    _seekGateTimeout?.cancel();
    _pageController.dispose();
    unawaited(_brightnessNotifier.resetBrightness());
    WakelockPlus.disable();
    unawaited(_setReaderSystemBarsVisible(true));
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

  /// Whether the page(s) at [pageIndexes], which just became visible, should
  /// count toward the session total, and consumes the pending seek if so.
  ///
  /// A slider seek animates across the gap, and every page the animation
  /// sweeps past reports a page change — a long drag would otherwise add a
  /// large chunk of the volume to the session. While a seek is in flight only
  /// the page the user actually asked for counts; reaching it ends the seek.
  bool _consumeSeekGate(List<int> pageIndexes) {
    final target = _pendingSeekTarget;
    if (target == null) return true;
    if (!pageIndexes.contains(target)) return false;
    _pendingSeekTarget = null;
    return true;
  }

  /// Records the slider's current destination, so the pages swept past on the
  /// way there aren't counted.
  ///
  /// A seek to a page that is already on screen reports no page change at all,
  /// so it is cleared immediately instead of being left pending. The timeout
  /// is the backstop for the seeks that can't be resolved exactly — an
  /// interrupted animation, or scroll view, whose page estimate is derived
  /// from viewport heights and can settle a page short of its target.
  void _setSeekTarget(
    int page,
    MangaViewMode viewMode,
    List<PageSpread> spreads,
  ) {
    _seekGateTimeout?.cancel();
    if (_visiblePageIndexes(viewMode, spreads).contains(page)) {
      _pendingSeekTarget = null;
      return;
    }
    _pendingSeekTarget = page;
    _seekGateTimeout = Timer(
      const Duration(seconds: 1),
      () => _pendingSeekTarget = null,
    );
  }

  /// Adds the characters on [pageIndexes] to the session total.
  ///
  /// Callers must invoke this only on a genuine page-change or initial-display
  /// transition — never per rebuild — since a page that becomes visible again
  /// is intentionally counted again (the EPUB reader counts on every
  /// relocation, so both formats measure "characters displayed").
  ///
  /// Counting happens at display time, so a page shown before its OCR has
  /// finished contributes the characters it had then — zero for a page with no
  /// OCR text yet, permanently.
  void _recordPageCharacters(MokuroBook book, Iterable<int> pageIndexes) {
    for (final index in pageIndexes) {
      if (index < 0 || index >= book.pages.length) continue;
      _sessionTracker.recordCharactersRead(charCountForPage(book.pages[index]));
    }
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
      // Page-turn telemetry deliberately still counts seek sweeps.
      _recordPageTurn(forward: page > _currentPage);
      final displayed = displayedPages ?? [page];
      if (_consumeSeekGate(displayed)) {
        _recordPageCharacters(book, displayed);
      }
    }
    setState(() => _currentPage = page);

    // Save progress
    final progress = totalPages > 1 ? page / (totalPages - 1) : 0.0;
    ref
        .read(bookRepositoryProvider)
        .updateProgress(widget.book.id, page.toString(), progress: progress);

    _precacheAdjacentPages(page, totalPages);
  }

  /// Precache the next few pages so they display instantly when swiped to.
  void _precacheAdjacentPages(int currentPage, int totalPages) {
    final asyncBook = ref.read(mangaPagesProvider(widget.book.id));
    final mokuroBook = switch (asyncBook) {
      AsyncData<MokuroBook>(:final value) => value,
      _ => null,
    };
    if (mokuroBook == null || !mounted) return;

    const pagesToPrecache = 5;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = (screenWidth * dpr).toInt();

    for (var i = 1; i <= pagesToPrecache; i++) {
      final idx = currentPage + i;
      if (idx >= totalPages) break;

      final page = mokuroBook.pages[idx];

      // SAF images are loaded via platform channel in AndroidSafImage,
      // so we can only precache file-backed images here.
      if (mokuroBook.safTreeUri != null) continue;

      final path = '${mokuroBook.imageDirPath}/${page.imageFileName}';
      final file = File(path);
      if (!file.existsSync()) continue;

      precacheImage(ResizeImage(FileImage(file), width: cacheWidth), context);
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
    unawaited(_setReaderSystemBarsVisible(visible));
  }

  Future<void> _setReaderSystemBarsVisible(bool visible) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;

    try {
      await _systemUiChannel.invokeMethod<void>('setSystemBarsVisible', {
        'visible': visible,
      });
    } catch (_) {
      // Best effort only; the reader still works if the native host declines
      // the request on a non-Android platform or older embedder.
    }
  }

  /// Whether programmatic page turns animate (off for e-reader displays).
  bool get _animatePageTurns =>
      ref.read(readerSettingsProvider).mangaPageTurnAnimation;

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
      barrierLabel: 'Dismiss',
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
    await _setReaderSystemBarsVisible(true);
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ReadingSettingsScreen()));
    if (!mounted) return;
    await _setReaderSystemBarsVisible(_showControls);
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
    final (viewMode, direction, mangaAutoCropEnabled) = ref.watch(
      readerSettingsProvider.select(
        (s) => (s.mangaViewMode, s.mangaReadingDirection, s.mangaAutoCrop),
      ),
    );
    final isProUnlocked = proUnlockedValue(ref.watch(proUnlockedProvider));
    final autoCrop = isProUnlocked && mangaAutoCropEnabled;
    final isOcrRunning = ref.watch(isOcrRunningProvider(widget.book.id));
    final enableWordOverlays = !isOcrRunning;
    final bottomSliderPadding = bottomControlPadding(MediaQuery.of(context));

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _mangaReaderOverlayStyle,
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
                    'Failed to load manga',
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
              return const Center(
                child: Text(
                  'No pages found',
                  style: TextStyle(color: Colors.white),
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
              if (mounted) _precacheAdjacentPages(_currentPage, totalPages);
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
                // Page content with tap zones
                GestureDetector(
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
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Colors.black87, Colors.transparent],
                        ),
                      ),
                      child: SafeArea(
                        top: false,
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            16,
                            0,
                            16,
                            bottomSliderPadding,
                          ),
                          child: Row(
                            children: [
                              Text(
                                '${_currentPage + 1}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                              ),
                              Expanded(
                                child: Directionality(
                                  textDirection: isRtl
                                      ? TextDirection.rtl
                                      : TextDirection.ltr,
                                  child: Slider(
                                    value: _currentPage.toDouble(),
                                    min: 0,
                                    max: (totalPages - 1).toDouble(),
                                    divisions: totalPages > 1
                                        ? totalPages - 1
                                        : null,
                                    onChanged: (value) {
                                      final page = value.round();
                                      _setSeekTarget(page, viewMode, spreads);
                                      switch (viewMode) {
                                        case MangaViewMode.singlePage:
                                          _goToPage(page, totalPages);
                                        case MangaViewMode.twoPageSpread:
                                          final si = spreadIndexForPage(
                                            spreads,
                                            page,
                                          );
                                          _spreadViewKey.currentState
                                              ?.goToSpread(
                                                si,
                                                animate: _animatePageTurns,
                                              );
                                        case MangaViewMode.scroll:
                                          _scrollViewKey.currentState
                                              ?.scrollToPage(
                                                page,
                                                animate: _animatePageTurns,
                                              );
                                      }
                                    },
                                    // The last division dragged over is the
                                    // page the user meant; re-evaluating on
                                    // release also clears the seek when the
                                    // animation already arrived there.
                                    onChangeEnd: (value) => _setSeekTarget(
                                      value.round(),
                                      viewMode,
                                      spreads,
                                    ),
                                  ),
                                ),
                              ),
                              Text(
                                '$totalPages',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
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
          physics: _isZoomed
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
            // Fires on every scroll tick, so count only when the page at the
            // viewport centre actually changes — and not while a slider seek
            // is animating past it.
            if (page != _currentPage && _consumeSeekGate([page])) {
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
