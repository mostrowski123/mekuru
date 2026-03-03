import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/library/presentation/providers/library_providers.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/data/services/ocr_background_worker.dart';
import 'package:mekuru/features/manga/presentation/providers/manga_reader_providers.dart';
import 'package:mekuru/features/manga/presentation/providers/pro_access_provider.dart';
import 'package:mekuru/features/manga/data/services/page_spread_calculator.dart';
import 'package:mekuru/features/manga/presentation/screens/pro_upgrade_screen.dart';
import 'package:mekuru/features/manga/presentation/widgets/manga_page_view.dart';
import 'package:mekuru/features/manga/presentation/widgets/manga_scroll_view.dart';
import 'package:mekuru/features/manga/presentation/widgets/manga_spread_view.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/manga/presentation/providers/ocr_progress_provider.dart';
import 'package:mekuru/features/reader/presentation/reader_interaction_logic.dart';
import 'package:mekuru/features/reader/presentation/widgets/lookup_sheet.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/shared/utils/system_gesture_padding.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class _MangaReaderScreenState extends ConsumerState<MangaReaderScreen> {
  late PageController _pageController;
  int _currentPage = 0;
  bool _showControls = false;
  bool _isZoomed = false;
  bool _debugOverlay = false;
  bool _isComputingAutoCrop = false;
  bool _autoCropComputedThisSession = false;

  // View mode keys for cross-widget navigation
  final _scrollViewKey = GlobalKey<MangaScrollViewState>();
  final _spreadViewKey = GlobalKey<MangaSpreadViewState>();

  // Word highlight state — shown while a lookup sheet is active
  MokuroWord? _highlightedWord;
  int? _highlightedPageIndex;

  @override
  void initState() {
    super.initState();
    // Restore last read page from book's lastReadCfi.
    // Scroll mode stores offset as 'scroll:<offset>' — default to page 0.
    final cfi = widget.book.lastReadCfi ?? '';
    _currentPage = cfi.startsWith('scroll:') ? 0 : (int.tryParse(cfi) ?? 0);
    _pageController = PageController(initialPage: _currentPage);

    // Enter immersive mode
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Dismiss the library's "OCR Complete" overlay after the user opens
    // this manga once.
    unawaited(_acknowledgeCompletedOcrOverlay());
  }

  @override
  void dispose() {
    _pageController.dispose();
    // Restore system UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _onPageChanged(int page, int totalPages) {
    setState(() => _currentPage = page);

    // Save progress
    final progress = totalPages > 1 ? page / (totalPages - 1) : 0.0;
    ref
        .read(bookRepositoryProvider)
        .updateProgress(widget.book.id, page.toString(), progress: progress);
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
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  void _goToPage(int page, int totalPages) {
    final clamped = page.clamp(0, totalPages - 1);
    _pageController.animateToPage(
      clamped,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  /// Navigate forward or backward by [delta] pages/spreads depending on mode.
  void _navigate(int delta, int totalPages, List<PageSpread> spreads) {
    final viewMode = ref.read(mangaViewModeProvider);
    switch (viewMode) {
      case MangaViewMode.singlePage:
        _goToPage(_currentPage + delta, totalPages);
      case MangaViewMode.twoPageSpread:
        if (spreads.isNotEmpty) {
          final si = spreadIndexForPage(spreads, _currentPage);
          _spreadViewKey.currentState?.goToSpread(si + delta);
        }
      case MangaViewMode.scroll:
        _scrollViewKey.currentState?.scrollToPage(_currentPage + delta);
    }
  }

  double _parseScrollOffset(String? cfi) =>
      double.tryParse(cfi?.replaceFirst('scroll:', '') ?? '') ?? 0.0;

  void _clearHighlight() {
    if (_highlightedWord != null) {
      setState(() {
        _highlightedWord = null;
        _highlightedPageIndex = null;
      });
    }
  }

  void _onWordTapped(
    MokuroWord word,
    MokuroTextBlock block,
    Offset globalPosition,
  ) {
    // Build context sentence from all lines in the block
    final sentence = block.lines.join();

    // Determine top vs bottom positioning — if the word is in the bottom
    // half of the screen, show the sheet at the top to avoid covering it.
    final screenHeight = MediaQuery.of(context).size.height;
    final showAtTop = globalPosition.dy > screenHeight * 0.5;

    // Read transparency preference
    final transparent = ref.read(mangaLookupTransparencyProvider);

    // Set highlight on the page
    setState(() {
      _highlightedWord = word;
      _highlightedPageIndex = _currentPage;
    });

    // Hide controls if visible
    if (_showControls) {
      setState(() => _showControls = false);
    }

    if (showAtTop) {
      _showTopSheet(word, sentence, transparent).then((_) => _clearHighlight());
    } else {
      _showBottomSheet(
        word,
        sentence,
        transparent,
      ).then((_) => _clearHighlight());
    }
  }

  Future<void> _showBottomSheet(
    MokuroWord word,
    String sentence,
    bool transparent,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: transparent ? Colors.transparent : null,
      barrierColor: transparent ? Colors.black.withAlpha(30) : null,
      builder: (_) => LookupSheet(
        selectedText: word.dictionaryForm ?? word.surface,
        surfaceForm: word.surface,
        sentenceContext: sentence,
        editable: true,
        transparent: transparent,
        onEditingStarted: () {
          setState(() {
            _highlightedWord = word;
            _highlightedPageIndex = _currentPage;
          });
        },
        onEditingEnded: () {
          // Keep highlight while sheet is still open
        },
      ),
    );
  }

  Future<void> _showTopSheet(
    MokuroWord word,
    String sentence,
    bool transparent,
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
              selectedText: word.dictionaryForm ?? word.surface,
              surfaceForm: word.surface,
              sentenceContext: sentence,
              showAtTop: true,
              editable: true,
              transparent: transparent,
              onEditingStarted: () {
                setState(() {
                  _highlightedWord = word;
                  _highlightedPageIndex = _currentPage;
                });
              },
              onEditingEnded: () {
                // Keep highlight while sheet is still open
              },
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

    final screenSize = MediaQuery.of(context).size;
    final normalizedX = details.localPosition.dx / screenSize.width;
    final normalizedY = details.localPosition.dy / screenSize.height;

    final direction = ref.read(mangaReadingDirectionProvider);
    final readerDir = direction == MangaReadingDirection.rtl
        ? ReaderDirection.rtl
        : ReaderDirection.ltr;

    final intent = resolveTapIntent(
      normalizedX: normalizedX,
      normalizedY: normalizedY,
      readingDirection: readerDir,
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
    await openProUpgrade(context, ref);
  }

  void _showSettingsSheet(MokuroBook mokuroBook) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final viewMode = ref.watch(mangaViewModeProvider);
          final direction = ref.watch(mangaReadingDirectionProvider);
          final transparent = ref.watch(mangaLookupTransparencyProvider);
          final autoCrop = ref.watch(mangaAutoCropProvider);
          final hasComputedAutoCrop =
              mokuroBook.autoCropVersion > 0 ||
              mokuroBook.pages.any((page) => page.contentBounds != null);
          final isProUnlocked = proUnlockedValue(
            ref.watch(proUnlockedProvider),
          );
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reader Settings',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  // View mode selector
                  SegmentedButton<MangaViewMode>(
                    segments: const [
                      ButtonSegment(
                        value: MangaViewMode.singlePage,
                        icon: Icon(Icons.looks_one),
                        label: Text('Single'),
                      ),
                      ButtonSegment(
                        value: MangaViewMode.twoPageSpread,
                        icon: Icon(Icons.looks_two),
                        label: Text('Spread'),
                      ),
                      ButtonSegment(
                        value: MangaViewMode.scroll,
                        icon: Icon(Icons.view_day),
                        label: Text('Scroll'),
                      ),
                    ],
                    selected: {viewMode},
                    onSelectionChanged: (value) {
                      ref
                          .read(mangaViewModeProvider.notifier)
                          .setMode(value.first);
                    },
                  ),
                  const SizedBox(height: 8),
                  // Reading direction
                  ListTile(
                    leading: const Icon(Icons.swap_horiz),
                    title: const Text('Reading Direction'),
                    subtitle: Text(
                      direction == MangaReadingDirection.rtl
                          ? 'Right to Left'
                          : 'Left to Right',
                    ),
                    onTap: () {
                      ref.read(mangaReadingDirectionProvider.notifier).toggle();
                    },
                  ),
                  // Auto-crop toggle
                  if (isProUnlocked)
                    SwitchListTile(
                      secondary: const Icon(Icons.crop),
                      title: const Text('Auto-Crop'),
                      subtitle: const Text('Remove empty margins'),
                      value: autoCrop,
                      onChanged: (value) =>
                          _handleAutoCropToggle(ref, mokuroBook, value),
                    )
                  else
                    ListTile(
                      enabled: false,
                      leading: Icon(
                        Icons.crop,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      title: const Text('Auto-Crop'),
                      subtitle: const Text('Remove empty margins'),
                      trailing: TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _openProUpgradeFromReader();
                        },
                        child: const Text('Unlock'),
                      ),
                    ),
                  if (isProUnlocked && autoCrop && hasComputedAutoCrop)
                    ListTile(
                      leading: const Icon(Icons.refresh),
                      title: const Text('Re-run Auto-Crop'),
                      subtitle: const Text(
                        'Re-scan every page image for this book',
                      ),
                      onTap: () => _handleAutoCropRerun(ref),
                    ),
                  // Transparent lookup toggle
                  SwitchListTile(
                    secondary: const Icon(Icons.opacity),
                    title: const Text('Transparent Lookup'),
                    subtitle: const Text('See-through dictionary sheet'),
                    value: transparent,
                    onChanged: (value) {
                      ref
                          .read(mangaLookupTransparencyProvider.notifier)
                          .toggle();
                    },
                  ),
                  // Debug overlay toggle
                  SwitchListTile(
                    secondary: const Icon(Icons.grid_on),
                    title: const Text('Debug Word Overlay'),
                    subtitle: const Text('Show word bounding boxes'),
                    value: _debugOverlay,
                    onChanged: (value) {
                      setState(() => _debugOverlay = value);
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
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
      ref.read(mangaAutoCropProvider.notifier).setEnabled(false);
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
      ref.read(mangaAutoCropProvider.notifier).setEnabled(true);
      return;
    }

    await _runAutoCropComputation(ref, force: false, enableAfterCompute: true);
  }

  Future<void> _handleAutoCropRerun(WidgetRef ref) {
    return _runAutoCropComputation(
      ref,
      force: true,
      enableAfterCompute: ref.read(mangaAutoCropProvider),
    );
  }

  Future<void> _runAutoCropComputation(
    WidgetRef ref, {
    required bool force,
    required bool enableAfterCompute,
  }) async {
    if (_isComputingAutoCrop) return;
    final whiteThreshold = ref.read(autoCropWhiteThresholdProvider);

    final dialogTitle = force ? 'Re-run Auto-Crop?' : 'Compute Auto-Crop?';
    final dialogBody = force
        ? 'Auto-crop will re-scan every page image for this book and '
              'replace the saved crop bounds. This may take a minute.'
        : 'Auto-crop needs to scan every page image for this book before it '
              'can be enabled. This may take a minute.';
    final progressBody = force
        ? 'Recomputing auto-crop bounds. This may take a minute.'
        : 'Computing auto-crop bounds. This may take a minute.';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogTitle),
        content: Text(dialogBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Continue'),
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
      ref.read(mangaAutoCropProvider.notifier).setEnabled(enableAfterCompute);
      if (force && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Auto-crop bounds refreshed.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Auto-crop setup failed: $e')));
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
    final direction = ref.watch(mangaReadingDirectionProvider);
    final isProUnlocked = proUnlockedValue(ref.watch(proUnlockedProvider));
    final autoCrop = isProUnlocked && ref.watch(mangaAutoCropProvider);
    final viewMode = ref.watch(mangaViewModeProvider);
    final isOcrRunning = ref.watch(isOcrRunningProvider(widget.book.id));
    final enableWordOverlays = !isOcrRunning;
    final bottomSliderPadding = bottomControlPadding(MediaQuery.of(context));

    return Scaffold(
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

          final isRtl = direction == MangaReadingDirection.rtl;
          final spreads = viewMode == MangaViewMode.twoPageSpread
              ? computeSpreads(totalPages, isRtl: isRtl)
              : <PageSpread>[];

          return Stack(
            children: [
              // Page content with tap zones
              GestureDetector(
                onTapUp: (details) => _handleTap(details, totalPages, spreads),
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
                                    switch (viewMode) {
                                      case MangaViewMode.singlePage:
                                        _goToPage(page, totalPages);
                                      case MangaViewMode.twoPageSpread:
                                        final si = spreadIndexForPage(
                                          spreads,
                                          page,
                                        );
                                        _spreadViewKey.currentState?.goToSpread(
                                          si,
                                        );
                                      case MangaViewMode.scroll:
                                        _scrollViewKey.currentState
                                            ?.scrollToPage(page);
                                    }
                                  },
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
          onPageChanged: (page) => _onPageChanged(page, totalPages),
          itemBuilder: (context, index) {
            final page = mokuroBook.pages[index];
            return MangaPageView(
              page: page,
              imageDirPath: mokuroBook.imageDirPath,
              safTreeUri: mokuroBook.safTreeUri,
              safImageDirRelativePath: mokuroBook.safImageDirRelativePath,
              debugOverlay: _debugOverlay,
              autoCrop: autoCrop,
              enableWordOverlays: enableWordOverlays,
              highlightedWord: index == _highlightedPageIndex
                  ? _highlightedWord
                  : null,
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
          debugOverlay: _debugOverlay,
          autoCrop: autoCrop,
          enableWordOverlays: enableWordOverlays,
          highlightedWord: _highlightedWord,
          highlightedPageIndex: _highlightedPageIndex,
          onWordTapped: _onWordTapped,
          onZoomChanged: (zoomed) {
            if (zoomed != _isZoomed) {
              setState(() => _isZoomed = zoomed);
            }
          },
          onSpreadChanged: (spreadIdx) {
            if (spreadIdx >= 0 && spreadIdx < spreads.length) {
              final page = spreads[spreadIdx].primaryPageIndex;
              _onPageChanged(page, totalPages);
            }
          },
        );

      case MangaViewMode.scroll:
        return MangaScrollView(
          key: _scrollViewKey,
          mokuroBook: mokuroBook,
          bookId: widget.book.id,
          initialScrollOffset: _parseScrollOffset(widget.book.lastReadCfi),
          debugOverlay: _debugOverlay,
          autoCrop: autoCrop,
          enableWordOverlays: enableWordOverlays,
          highlightedWord: _highlightedWord,
          highlightedPageIndex: _highlightedPageIndex,
          onWordTapped: _onWordTapped,
          onPageEstimateChanged: (page) {
            setState(() => _currentPage = page);
            // Progress is saved by MangaScrollView's debounced callback
          },
        );
    }
  }
}
