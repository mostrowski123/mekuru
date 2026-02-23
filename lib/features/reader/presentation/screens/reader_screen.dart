import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/library/data/services/epub_parser.dart';
import 'package:mekuru/features/reader/data/models/book_reading_config.dart';
import 'package:mekuru/features/reader/data/models/epub_models.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/data/services/epub_file_resolver.dart';
import 'package:mekuru/features/reader/data/services/mecab_service.dart';
import 'package:mekuru/features/reader/data/services/reader_progress_persistence.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/features/reader/presentation/reader_display_settings_mapper.dart';
import 'package:mekuru/features/reader/presentation/reader_interaction_logic.dart';
import 'package:mekuru/features/reader/data/models/highlight_color.dart';
import 'package:mekuru/features/reader/presentation/widgets/bookmarks_sheet.dart';
import 'package:mekuru/features/reader/presentation/widgets/custom_epub_controller.dart';
import 'package:mekuru/features/reader/presentation/widgets/custom_epub_viewer.dart';
import 'package:mekuru/features/reader/presentation/widgets/highlights_sheet.dart';
import 'package:mekuru/features/reader/presentation/widgets/lookup_sheet.dart';
import 'package:mekuru/shared/utils/haptics.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// EPUB reader backed by a custom epub.js WebView bridge.
class ReaderScreen extends ConsumerStatefulWidget {
  final Book book;

  const ReaderScreen({super.key, required this.book});

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  final _epubController = CustomEpubController();
  final _epubFileResolver = EpubFileResolver();

  late final ReaderProgressPersistence _progressPersistence;

  Uint8List? _epubData;
  List<_FlattenedChapter> _chapters = const [];
  bool _isLoading = true;
  bool _showControls = true;
  bool _isEpubLoaded = false;
  bool _isRebuildingForDirection = false;
  bool _hasActiveSelection = false;
  bool _locationsReady = false;
  EpubSelectionData? _selectionData;
  double _progress = 0.0;
  String _currentCfi = '';
  bool _isCurrentPageBookmarked = false;
  String? _initialCfi;
  String? _errorMessage;
  int _viewerEpoch = 0;

  // Book language (from DB or re-parsed for legacy books).
  String? _bookLanguage;

  // Touch tracking for swipe vs. tap detection.
  double? _touchDownX;
  double? _touchDownY;

  @override
  void initState() {
    super.initState();

    Sentry.addBreadcrumb(Breadcrumb(
      message: 'Opened book',
      category: 'reader',
    ));

    _progressPersistence = ReaderProgressPersistence(
      saveProgress: (cfi, progress) {
        return ref.read(readerBookRepositoryProvider).updateProgress(
          widget.book.id,
          cfi,
          progress: progress,
        );
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await ref.read(readerSettingsProvider.notifier).loadPersistedSettings();
      if (!mounted) return;

      // Apply book-specific defaults (or per-book overrides if the user
      // previously changed the display settings for this book).
      _bookLanguage = widget.book.language;
      ref.read(readerSettingsProvider.notifier).applyBookDefaults(
        bookId: widget.book.id,
        language: widget.book.language,
        pageProgressionDirection: widget.book.pageProgressionDirection,
        primaryWritingMode: widget.book.primaryWritingMode,
        overrideVerticalText: widget.book.overrideVerticalText,
        overrideReadingDirection: widget.book.overrideReadingDirection,
      );

      final settings = ref.read(readerSettingsProvider);
      if (settings.keepScreenOn) {
        WakelockPlus.enable();
      }
      await ref.read(brightnessProvider.notifier).initialize();

      if (!mounted) return;
      await _loadEpubData();
    });
  }

  @override
  void dispose() {
    unawaited(_progressPersistence.dispose());
    ref.read(brightnessProvider.notifier).resetBrightness();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(readerSettingsProvider);

    ref.listen<ReaderSettings>(readerSettingsProvider, (previous, next) {
      if (previous == null) {
        return;
      }

      if (previous.readingDirection != next.readingDirection ||
          previous.verticalText != next.verticalText) {
        debugPrint(
          '[READER] direction/verticalText changed: '
          'dir=${next.readingDirection} '
          'vertical=${next.verticalText} '
          '(was dir=${previous.readingDirection} '
          'vertical=${previous.verticalText})',
        );
        unawaited(_rebuildViewerForDirectionChange());
      }

      if (previous.fontSize != next.fontSize && _isEpubLoaded) {
        _epubController.setFontSize(next.fontSize);
      }

      final marginsChanged =
          previous.horizontalPadding != next.horizontalPadding ||
          previous.verticalPadding != next.verticalPadding;
      if (marginsChanged && _isEpubLoaded) {
        _epubController.setMargins(
          next.horizontalPadding,
          next.verticalPadding,
        );
      }

      if (previous.disableLinks != next.disableLinks && _isEpubLoaded) {
        _epubController.setDisableLinks(next.disableLinks);
      }

      final colorChanged = previous.colorMode != next.colorMode ||
          (next.colorMode == ColorMode.sepia &&
              previous.sepiaIntensity != next.sepiaIntensity);
      if (colorChanged && _isEpubLoaded) {
        final newTheme = buildReaderTheme(settings: next);
        _epubController.updateTheme(
          foregroundColor: newTheme.foregroundColor,
          customCss: newTheme.customCss,
        );
        _epubController.setBodyBackground(newTheme.backgroundColor);
      }
    });

    final readerTheme = buildReaderTheme(settings: settings);

    return Scaffold(
      backgroundColor: readerTheme.backgroundColor,
      body: _errorMessage != null
          ? _buildErrorState(context)
          : Stack(
              children: [
                if (_epubData != null)
                  Positioned.fill(
                    child: CustomEpubViewer(
                      key: ValueKey('reader-${widget.book.id}-$_viewerEpoch'),
                      controller: _epubController,
                      epubData: _epubData!,
                      initialCfi: _initialCfi,
                      // epub.js uses direction to determine its pagination axis:
                      // 'rtl' → vertical axis (for vertical Japanese text),
                      // 'ltr' → horizontal axis.
                      // When vertical text is disabled, we MUST pass 'ltr' so
                      // epub.js paginates horizontally, regardless of the
                      // user's reading direction (which only affects tap zones
                      // and swipe interpretation in Dart).
                      direction: settings.verticalText &&
                              settings.readingDirection == ReaderDirection.rtl
                          ? 'rtl'
                          : 'ltr',
                      fontSize: settings.fontSize.round(),
                      foregroundColor: readerTheme.foregroundColor,
                      backgroundColor: readerTheme.backgroundColor,
                      customCss: readerTheme.customCss,
                      horizontalMargin: settings.horizontalPadding,
                      verticalMargin: settings.verticalPadding,
                      // When vertical text is disabled, epub.js still reads
                      // the section's original writing-mode CSS and sets axis
                      // to vertical. This flag tells the JS bridge to force
                      // the axis back to horizontal after each section loads.
                      forceHorizontalAxis: !settings.verticalText,
                      onLoaded: () {
                        if (!mounted) return;
                        setState(() {
                          _isLoading = false;
                          _isEpubLoaded = true;
                        });
                        _restoreHighlights();
                        // Sync disableLinks setting to the JS bridge
                        final s = ref.read(readerSettingsProvider);
                        _epubController.setDisableLinks(s.disableLinks);
                      },
                      onChaptersLoaded: (chapters) {
                        if (!mounted) return;
                        debugPrint(
                          '[READER] onChaptersLoaded: ${chapters.length} '
                          'chapters received',
                        );
                        setState(() {
                          _chapters = _flattenChapters(chapters);
                        });
                        debugPrint(
                          '[READER] TOC flattened to ${_chapters.length} '
                          'entries',
                        );
                      },
                      onLocationsReady: () {
                        if (!mounted) return;
                        _locationsReady = true;
                      },
                      onRelocated: (location) {
                        if (!mounted) return;

                        final normalizedProgress = location.progress.clamp(
                          0.0,
                          1.0,
                        );

                        // Only trust progress values after epub.js has
                        // generated locations; before that, percentage is 0.
                        if (_locationsReady) {
                          setState(() => _progress = normalizedProgress);
                        }

                        final cfi = location.startCfi.trim();
                        if (_isEpubCfi(cfi)) {
                          _currentCfi = cfi;
                          _checkBookmarkState();
                          _progressPersistence.queueSave(
                            cfi,
                            _locationsReady ? normalizedProgress : _progress,
                          );
                        }
                      },
                      onSelection: (selection) {
                        _hasActiveSelection = true;
                        if (selection.text.isNotEmpty &&
                            selection.cfi.isNotEmpty) {
                          setState(() {
                            _selectionData = selection;
                          });
                        }
                      },
                      onSelectionCleared: () {
                        _hasActiveSelection = false;
                        setState(() {
                          _selectionData = null;
                        });
                      },
                      onTouchDown: (x, y) {
                        _touchDownX = x.clamp(0.0, 1.0);
                        _touchDownY = y.clamp(0.0, 1.0);
                        debugPrint(
                          '[READER] touchDown stored '
                          'x=${x.toStringAsFixed(3)} '
                          'y=${y.toStringAsFixed(3)}',
                        );
                      },
                      onTouchUp: (x, y) {
                        _handleTouchUp(
                          x,
                          y,
                          settings.readingDirection,
                          settings.swipeSensitivity,
                        );
                      },
                      onSentenceSelected: (selection) {
                        if (!mounted) return;
                        _hasActiveSelection = true;
                        setState(() {
                          _selectionData = selection;
                        });
                        AppHaptics.medium();
                      },
                      onWordTapped: (surroundingText, charOffset,
                          blockCharOffset, tappedChar, x, y) {
                        _handleWordTapped(
                          surroundingText,
                          charOffset,
                          blockCharOffset,
                          tappedChar,
                          x,
                          y,
                          settings.readingDirection,
                          settings.swipeSensitivity,
                        );
                      },
                    ),
                  ),
                if (_isLoading) _buildLoadingOverlay(context),
                if (_showControls && !_isLoading)
                  Positioned(top: 0, left: 0, right: 0, child: _buildTopBar()),
                if (_showControls && !_isLoading)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: _buildBottomBar(settings),
                  ),
                // Highlight speed-dial FAB — appears when text is selected
                if (_selectionData != null)
                  _HighlightSpeedDial(
                    onColorSelected: (color) => _createHighlight(
                      _selectionData!.cfi,
                      _selectionData!.text,
                      color,
                    ),
                    onExpandToSentence: () {
                      _epubController.expandToSentence();
                      AppHaptics.medium();
                    },
                  ),
              ],
            ),
    );
  }

  Future<void> _loadEpubData() async {
    setState(() {
      _isLoading = true;
      _isEpubLoaded = false;
      _locationsReady = false;
      _errorMessage = null;
      _chapters = const [];
      _progress = 0;
    });

    try {
      final epubPath = await _epubFileResolver.resolveLocalEpubPath(
        widget.book.filePath,
      );

      final latestBook = await ref
          .read(readerBookRepositoryProvider)
          .getBookById(widget.book.id);
      if (!mounted) return;

      final savedProgress = latestBook?.lastReadCfi ?? widget.book.lastReadCfi;
      final initialCfi = _extractInitialCfi(savedProgress);

      // Re-parse legacy books without language metadata to detect language.
      if (widget.book.language == null) {
        try {
          final metadata = await EpubParser.parseMetadataOnly(epubPath);
          if (!mounted) return;
          _bookLanguage = metadata.language;
          // Backfill the database so subsequent opens skip re-parsing.
          unawaited(
            ref.read(readerBookRepositoryProvider).backfillLanguage(
              widget.book.id,
              metadata.language,
              metadata.pageProgressionDirection,
              metadata.primaryWritingMode,
            ),
          );
          // Re-apply book defaults with detected language.
          // Legacy books won't have per-book overrides yet, so pass null.
          ref.read(readerSettingsProvider.notifier).applyBookDefaults(
            bookId: widget.book.id,
            language: metadata.language,
            pageProgressionDirection: metadata.pageProgressionDirection,
            primaryWritingMode: metadata.primaryWritingMode,
          );
        } catch (_) {
          // Best effort — continue with null language (assumes Japanese).
        }
      }

      final bytes = await File(epubPath).readAsBytes();
      if (!mounted) return;

      setState(() {
        _epubData = bytes;
        _initialCfi = initialCfi;
        _progress = latestBook?.readProgress ?? widget.book.readProgress;
        _viewerEpoch += 1;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load EPUB.\n$error';
      });
    }
  }

  Future<void> _rebuildViewerForDirectionChange() async {
    if (_isRebuildingForDirection || !_isEpubLoaded || _epubData == null) {
      return;
    }

    _isRebuildingForDirection = true;
    final settings = ref.read(readerSettingsProvider);
    final epubDir = settings.verticalText &&
            settings.readingDirection == ReaderDirection.rtl
        ? 'rtl'
        : 'ltr';
    debugPrint(
      '[READER] rebuilding viewer for direction change: '
      'epubDir=$epubDir '
      'readerDir=${settings.readingDirection} '
      'vertical=${settings.verticalText}',
    );
    try {
      String? currentCfi;
      try {
        final location = await _epubController.getCurrentLocation();
        if (_isEpubCfi(location.startCfi)) {
          currentCfi = location.startCfi;
        }
      } catch (_) {
        // Best effort only.
      }

      if (!mounted) return;
      setState(() {
        _initialCfi = currentCfi ?? _initialCfi;
        _isLoading = true;
        _isEpubLoaded = false;
        _viewerEpoch += 1;
      });
    } finally {
      _isRebuildingForDirection = false;
    }
  }

  /// Whether the current display mode differs from the book's native format.
  bool _isNonNativeDisplayMode(ReaderSettings settings) {
    final nativeVertical = defaultVerticalText(
      language: _bookLanguage,
      pageProgressionDirection: widget.book.pageProgressionDirection,
    );
    return settings.verticalText != nativeVertical;
  }

  /// Returns a short warning explaining the display mode mismatch.
  String _nonNativeDisplayWarning(ReaderSettings settings) {
    if (settings.verticalText) {
      return 'This book was not originally formatted for vertical text. '
          'Some display issues may occur.';
    }
    return 'This book was originally formatted for vertical text. '
        'Some display issues may occur in horizontal mode.';
  }

  void _handleTouchUp(
    double x,
    double y,
    ReaderDirection readingDirection,
    double swipeSensitivity,
  ) {
    if (_hasActiveSelection) {
      debugPrint('[READER] touchUp ignored — active selection');
      _touchDownX = null;
      _touchDownY = null;
      return;
    }

    final upX = x.clamp(0.0, 1.0);
    final upY = y.clamp(0.0, 1.0);
    final downX = _touchDownX;
    final downY = _touchDownY;

    // Reset touch tracking.
    _touchDownX = null;
    _touchDownY = null;

    if (downX == null) {
      debugPrint('[READER] touchUp ignored — no matching touchDown');
      return;
    }

    final dx = upX - downX;

    ReaderNavigationIntent intent;

    final gesture = classifyGesture(
      downX: downX,
      upX: upX,
      downY: downY,
      upY: upY,
      swipeThreshold: swipeSensitivity,
    );
    if (gesture == GestureType.verticalSwipeDown) {
      // Swipe down — show controls.
      debugPrint('[READER] SWIPE DOWN detected — showing controls');
      if (!_showControls) {
        setState(() => _showControls = true);
      }
      return;
    } else if (gesture == GestureType.verticalSwipeUp) {
      // Swipe up — dismiss controls only if they are showing.
      if (_showControls) {
        debugPrint('[READER] SWIPE UP detected — hiding controls');
        setState(() => _showControls = false);
      }
      return;
    } else if (gesture == GestureType.horizontalSwipe) {
      // Horizontal swipe — navigate based on swipe direction.
      final pseudoVelocityX = dx > 0 ? 500.0 : -500.0;
      intent = resolveSwipeIntent(
        velocityX: pseudoVelocityX,
        readingDirection: readingDirection,
      );
      debugPrint(
        '[READER] SWIPE detected: dx=${dx.toStringAsFixed(3)} '
        'direction=${dx > 0 ? "right" : "left"} '
        'intent=$intent',
      );
    } else {
      // This is a tap — use tap position for zone-based navigation.
      intent = resolveTapIntent(
        normalizedX: upX,
        normalizedY: upY,
        readingDirection: readingDirection,
      );
      debugPrint(
        '[READER] TAP detected: x=${upX.toStringAsFixed(3)} '
        'intent=$intent',
      );
    }

    _executeNavigationIntent(intent);
  }

  Future<void> _handleWordTapped(
    String surroundingText,
    int charOffset,
    int blockCharOffset,
    String tappedChar,
    double x,
    double y,
    ReaderDirection readingDirection,
    double swipeSensitivity,
  ) async {
    final downX = _touchDownX;
    final downY = _touchDownY;
    _touchDownX = null;
    _touchDownY = null;

    // Check if this was actually a swipe (finger moved far from start)
    if (downX != null) {
      final gesture = classifyGesture(
        downX: downX,
        upX: x.clamp(0.0, 1.0),
        downY: downY,
        upY: y.clamp(0.0, 1.0),
        swipeThreshold: swipeSensitivity,
      );
      if (gesture == GestureType.verticalSwipeDown) {
        debugPrint(
          '[READER] wordTapped was actually a SWIPE DOWN — showing controls',
        );
        if (!_showControls) {
          setState(() => _showControls = true);
        }
        return;
      }
      if (gesture == GestureType.verticalSwipeUp) {
        if (_showControls) {
          debugPrint(
            '[READER] wordTapped was actually a SWIPE UP — hiding controls',
          );
          setState(() => _showControls = false);
        }
        return;
      }
      if (gesture == GestureType.horizontalSwipe) {
        final dx = x.clamp(0.0, 1.0) - downX;
        final pseudoVelocityX = dx > 0 ? 500.0 : -500.0;
        final intent = resolveSwipeIntent(
          velocityX: pseudoVelocityX,
          readingDirection: readingDirection,
        );
        debugPrint(
          '[READER] wordTapped was actually a SWIPE, navigating: $intent',
        );
        _executeNavigationIntent(intent);
        return;
      }
    }

    // It's a tap on text — identify the word via MeCab and show lookup
    final mecab = ref.read(mecabServiceProvider);
    final identification =
        mecab.identifyWordWithContext(surroundingText, charOffset);
    if (identification == null) {
      debugPrint(
        '[READER] wordTapped but MeCab could not identify word '
        '(char="$tappedChar" offset=$charOffset)',
      );
      return;
    }

    // Try to find a longer compound word match in the dictionary.
    final resolver = ref.read(compoundWordResolverProvider);
    final compound = await resolver.resolve(identification);

    debugPrint(
      '[READER] wordTapped resolved: '
      'surface="${compound.surfaceForm}" '
      'dict="${compound.dictionaryForm}" '
      'tokens=${compound.tokenCount}',
    );

    if (!mounted) return;

    // Highlight the resolved word in the EPUB.
    // Compute the word's start offset in block-relative coordinates:
    // blockCharOffset is where the tapped char is in the block,
    // charOffset is where it is in the (possibly trimmed) surrounding text,
    // tokenStartOffset is where the token starts in the surrounding text.
    final blockWordStart =
        blockCharOffset - charOffset + compound.tokenStartOffset;
    _epubController.highlightWord(
      blockWordStart,
      compound.surfaceForm.length,
    );

    _showLookupSheet(
      WordLookupResult(
        surfaceForm: compound.surfaceForm,
        dictionaryForm: compound.dictionaryForm,
        reading: compound.reading,
        sentenceContext: compound.sentenceContext,
        tokenStartOffset: compound.tokenStartOffset,
      ),
      y.clamp(0.0, 1.0),
    );
  }

  void _showLookupSheet(WordLookupResult result, double normalizedY) {
    if (_showControls) {
      setState(() => _showControls = false);
    }

    final showAtTop = normalizedY > 0.5;

    void onDismissed() {
      _epubController.clearWordHighlight();
    }

    if (showAtTop) {
      _showTopSheet(result).then((_) => onDismissed());
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (context) => LookupSheet(
          selectedText: result.dictionaryForm,
          surfaceForm: result.surfaceForm,
          sentenceContext: result.sentenceContext,
        ),
      ).then((_) => onDismissed());
    }
  }

  Future<void> _showTopSheet(WordLookupResult result) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.topCenter,
          child: Material(
            color: Colors.transparent,
            child: LookupSheet(
              selectedText: result.dictionaryForm,
              surfaceForm: result.surfaceForm,
              sentenceContext: result.sentenceContext,
              showAtTop: true,
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -1),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          )),
          child: child,
        );
      },
    );
  }

  void _executeNavigationIntent(ReaderNavigationIntent intent) {
    debugPrint('[READER] executing intent: $intent');
    switch (intent) {
      case ReaderNavigationIntent.none:
        return;
      case ReaderNavigationIntent.toggleControls:
        setState(() => _showControls = !_showControls);
        return;
      case ReaderNavigationIntent.goForward:
        _goForward();
        return;
      case ReaderNavigationIntent.goBackward:
        _goBackward();
        return;
    }
  }

  void _goForward() {
    if (!_isEpubLoaded || _hasActiveSelection) {
      debugPrint(
        '[READER] goForward blocked: loaded=$_isEpubLoaded '
        'selection=$_hasActiveSelection',
      );
      return;
    }
    debugPrint('[READER] goForward executing');
    _epubController.next();
  }

  void _goBackward() {
    if (!_isEpubLoaded || _hasActiveSelection) {
      debugPrint(
        '[READER] goBackward blocked: loaded=$_isEpubLoaded '
        'selection=$_hasActiveSelection',
      );
      return;
    }
    debugPrint('[READER] goBackward executing');
    _epubController.prev();
  }

  void _jumpToProgress(double value) {
    if (!_isEpubLoaded) return;

    final clampedValue = value.clamp(0.0, 1.0);
    setState(() => _progress = clampedValue);
    _epubController.toProgressPercentage(clampedValue);
  }

  List<_FlattenedChapter> _flattenChapters(
    List<EpubChapter> chapters, {
    int depth = 0,
  }) {
    final flattened = <_FlattenedChapter>[];

    for (final chapter in chapters) {
      final indent = List.filled(depth, '  ').join();
      flattened.add(
        _FlattenedChapter(
          title: '$indent${chapter.title}',
          href: chapter.href,
        ),
      );
      if (chapter.subitems.isNotEmpty) {
        flattened.addAll(_flattenChapters(chapter.subitems, depth: depth + 1));
      }
    }

    return flattened;
  }

  bool _isEpubCfi(String value) => value.startsWith('epubcfi(');

  String? _extractInitialCfi(String? rawProgress) {
    if (rawProgress == null) {
      return null;
    }

    final value = rawProgress.trim();
    if (value.isEmpty) {
      return null;
    }

    if (value.startsWith('wadoku://reader')) {
      return null;
    }

    return _isEpubCfi(value) ? value : null;
  }

  // ── Bookmarks ────────────────────────────────────────────────────

  Future<void> _checkBookmarkState() async {
    if (_currentCfi.isEmpty) return;
    final existing = await ref
        .read(bookmarkRepositoryProvider)
        .getBookmarkAtCfi(widget.book.id, _currentCfi);
    if (mounted) {
      setState(() => _isCurrentPageBookmarked = existing != null);
    }
  }

  Future<void> _toggleBookmark() async {
    if (!_isEpubLoaded || _currentCfi.isEmpty) return;

    final repo = ref.read(bookmarkRepositoryProvider);
    final existing = await repo.getBookmarkAtCfi(widget.book.id, _currentCfi);
    if (existing != null) {
      await repo.deleteBookmark(existing.id);
      AppHaptics.light();
      if (mounted) {
        _checkBookmarkState();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bookmark removed'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } else {
      var chapterTitle = '';
      if (_chapters.isNotEmpty) {
        chapterTitle = _chapters.first.title;
        for (final ch in _chapters) {
          if (ch.title.trim().isNotEmpty) {
            chapterTitle = ch.title.trim();
          }
        }
      }

      await repo.addBookmark(
        bookId: widget.book.id,
        cfi: _currentCfi,
        progress: _progress,
        chapterTitle: chapterTitle,
      );
      AppHaptics.medium();
      if (mounted) {
        _checkBookmarkState();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Page bookmarked'),
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }

  void _showBookmarksSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => BookmarksSheet(
        bookId: widget.book.id,
        onNavigate: (cfi) {
          if (_isEpubLoaded) {
            _epubController.display(cfi: cfi);
          }
        },
        onBookmarkDeleted: _checkBookmarkState,
      ),
    );
  }

  void _showHighlightsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => HighlightsSheet(
        bookId: widget.book.id,
        onNavigate: (cfiRange) {
          if (_isEpubLoaded) {
            _epubController.display(cfi: cfiRange);
          }
        },
        onRemoveHighlight: (cfiRange) {
          _epubController.removeHighlight(cfiRange);
        },
      ),
    );
  }

  // ── Highlights ──────────────────────────────────────────────────

  Future<void> _restoreHighlights() async {
    final highlights = await ref
        .read(highlightRepositoryProvider)
        .getAllHighlightsForBook(widget.book.id);
    for (final h in highlights) {
      final color = HighlightColor.fromName(h.color);
      _epubController.addHighlight(cfi: h.cfiRange, color: color.color);
    }
    if (highlights.isNotEmpty) {
      debugPrint('[READER] restored ${highlights.length} highlights');
    }
  }

  void _createHighlight(String cfi, String text, HighlightColor color) {
    if (cfi.isEmpty) return;

    ref.read(highlightRepositoryProvider).addHighlight(
      bookId: widget.book.id,
      cfiRange: cfi,
      selectedText: text,
      color: color.name,
    );
    _epubController.addHighlight(cfi: cfi, color: color.color);
    _dismissSelectionBar();
    AppHaptics.medium();
  }

  void _dismissSelectionBar() {
    _epubController.clearSelection();
    setState(() {
      _selectionData = null;
      _hasActiveSelection = false;
    });
  }

  Widget _buildTopBar() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
              tooltip: 'Back',
            ),
            Expanded(
              child: Text(
                widget.book.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_chapters.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.list, color: Colors.white),
                tooltip: 'Table of Contents',
                onPressed: () => _showChapterDrawer(context),
              ),
            IconButton(
              icon: Icon(
                _isCurrentPageBookmarked
                    ? Icons.bookmark
                    : Icons.bookmark_border,
                color: _isCurrentPageBookmarked
                    ? Colors.amber
                    : Colors.white,
              ),
              tooltip: _isCurrentPageBookmarked
                  ? 'Remove Bookmark'
                  : 'Bookmark Page',
              onPressed: _toggleBookmark,
            ),
            IconButton(
              icon: const Icon(Icons.bookmarks_outlined, color: Colors.white),
              tooltip: 'View Bookmarks',
              onPressed: _showBookmarksSheet,
            ),
            IconButton(
              icon: const Icon(Icons.highlight, color: Colors.white),
              tooltip: 'Highlights',
              onPressed: _showHighlightsSheet,
            ),
            IconButton(
              icon: const Icon(Icons.settings, color: Colors.white),
              tooltip: 'Settings',
              onPressed: () {
                AppHaptics.light();
                _showSettingsSheet(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(ReaderSettings settings) {
    final isRtl = settings.readingDirection == ReaderDirection.rtl;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    '${(_progress * 100).toInt()}%',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  Expanded(
                    child: Slider(
                      value: _progress.clamp(0.0, 1.0),
                      onChanged: _isEpubLoaded ? _jumpToProgress : null,
                      activeColor: Colors.white,
                      inactiveColor: Colors.white24,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.navigate_before, color: Colors.white),
                    tooltip: isRtl ? 'Next Page' : 'Previous Page',
                    onPressed: _isEpubLoaded
                        ? (isRtl ? _goForward : _goBackward)
                        : null,
                  ),
                  const SizedBox(width: 32),
                  IconButton(
                    icon: const Icon(Icons.navigate_next, color: Colors.white),
                    tooltip: isRtl ? 'Previous Page' : 'Next Page',
                    onPressed: _isEpubLoaded
                        ? (isRtl ? _goBackward : _goForward)
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingOverlay(BuildContext context) {
    return Container(
      color: Colors.white,
      child: const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? 'Unknown reader error.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _loadEpubData,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showChapterDrawer(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Table of Contents',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: _chapters.length,
                itemBuilder: (context, index) {
                  final chapter = _chapters[index];
                  return ListTile(
                    title: Text(chapter.title),
                    onTap: () {
                      Navigator.pop(context);
                      if (!_isEpubLoaded) return;
                      _epubController.display(cfi: chapter.href);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSettingsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final settings = ref.watch(readerSettingsProvider);
          final notifier = ref.read(readerSettingsProvider.notifier);
          final brightness = ref.watch(brightnessProvider);
          final brightnessNotifier = ref.read(brightnessProvider.notifier);

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.55,
            maxChildSize: 0.85,
            builder: (context, scrollController) => Padding(
              padding: const EdgeInsets.all(24),
              child: ListView(
                controller: scrollController,
                children: [
                  Text(
                    'Quick Settings',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 24),

                  // ── Font Size ──
                  Row(
                    children: [
                      const Icon(Icons.text_fields),
                      const SizedBox(width: 8),
                      const Text('Font Size'),
                      const Spacer(),
                      Text('${settings.fontSize.round()}'),
                    ],
                  ),
                  Slider(
                    value: settings.fontSize,
                    min: 12,
                    max: 32,
                    divisions: 20,
                    label: '${settings.fontSize.round()}',
                    onChanged: (value) {
                      AppHaptics.light();
                      notifier.setFontSize(value);
                    },
                  ),
                  const SizedBox(height: 16),

                  // ── Brightness ──
                  Row(
                    children: [
                      const Icon(Icons.brightness_low),
                      Expanded(
                        child: Slider(
                          value: brightness ?? 0.5,
                          min: 0.0,
                          max: 1.0,
                          onChanged: (value) {
                            AppHaptics.light();
                            brightnessNotifier.setBrightness(value);
                          },
                        ),
                      ),
                      const Icon(Icons.brightness_high),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── Color Mode ──
                  SegmentedButton<ColorMode>(
                    segments: const [
                      ButtonSegment(
                        value: ColorMode.normal,
                        label: Text('Normal'),
                        icon: Icon(Icons.brightness_5),
                      ),
                      ButtonSegment(
                        value: ColorMode.sepia,
                        label: Text('Sepia'),
                        icon: Icon(Icons.filter_vintage),
                      ),
                      ButtonSegment(
                        value: ColorMode.dark,
                        label: Text('Dark'),
                        icon: Icon(Icons.dark_mode),
                      ),
                    ],
                    selected: {settings.colorMode},
                    onSelectionChanged: (selection) {
                      AppHaptics.medium();
                      notifier.setColorMode(selection.first);
                    },
                  ),
                  if (settings.colorMode == ColorMode.sepia) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.coffee, size: 20),
                        Expanded(
                          child: Slider(
                            value: settings.sepiaIntensity,
                            min: 0.0,
                            max: 1.0,
                            onChanged: (value) {
                              AppHaptics.light();
                              notifier.setSepiaIntensity(value);
                            },
                          ),
                        ),
                        const Icon(Icons.local_fire_department, size: 20),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),

                  // ── Vertical Text (per-book) ──
                  SwitchListTile(
                    title: const Text('Vertical Text'),
                    subtitle: Text(
                      bookSupportsVerticalText(_bookLanguage)
                          ? 'This book'
                          : 'Not available for this book\'s language',
                    ),
                    value: settings.verticalText,
                    onChanged: bookSupportsVerticalText(_bookLanguage)
                        ? (value) {
                            AppHaptics.medium();
                            notifier.setVerticalText(value);
                          }
                        : null,
                    secondary: const Icon(Icons.text_rotation_angledown),
                  ),
                  if (_isNonNativeDisplayMode(settings))
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 16,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _nonNativeDisplayWarning(settings),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),

                  // ── Reading Direction (per-book) ──
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Reading Direction',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'This book',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SegmentedButton<ReaderDirection>(
                          segments: const [
                            ButtonSegment(
                              value: ReaderDirection.rtl,
                              label: Text('Right to Left'),
                            ),
                            ButtonSegment(
                              value: ReaderDirection.ltr,
                              label: Text('Left to Right'),
                            ),
                          ],
                          selected: {settings.readingDirection},
                          onSelectionChanged: (selection) {
                            AppHaptics.medium();
                            notifier.setReadingDirection(selection.first);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Disable Links ──
                  SwitchListTile(
                    title: const Text('Disable Links'),
                    subtitle: const Text(
                      'Tap linked text to look up words instead of navigating',
                    ),
                    value: settings.disableLinks,
                    onChanged: (value) {
                      AppHaptics.medium();
                      notifier.setDisableLinks(value);
                    },
                    secondary: const Icon(Icons.link_off),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FlattenedChapter {
  final String title;
  final String href;

  const _FlattenedChapter({required this.title, required this.href});
}

// ── Highlight speed-dial FAB ──────────────────────────────────────────

class _HighlightSpeedDial extends StatefulWidget {
  final void Function(HighlightColor color) onColorSelected;
  final VoidCallback onExpandToSentence;

  const _HighlightSpeedDial({
    required this.onColorSelected,
    required this.onExpandToSentence,
  });

  @override
  State<_HighlightSpeedDial> createState() => _HighlightSpeedDialState();
}

class _HighlightSpeedDialState extends State<_HighlightSpeedDial>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryController;
  late final Animation<double> _entryAnimation;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _entryAnimation = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutBack,
    );
    _entryController.forward();
  }

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final colors = HighlightColor.values;
    final theme = Theme.of(context);

    return Positioned(
      bottom: 100,
      right: 16,
      child: FadeTransition(
        opacity: _entryAnimation,
        child: ScaleTransition(
          scale: _entryAnimation,
          alignment: Alignment.bottomRight,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Color dots — shown when expanded
              for (var i = 0; i < colors.length; i++)
                AnimatedScale(
                  scale: _expanded ? 1.0 : 0.0,
                  duration: Duration(milliseconds: _expanded ? 150 + i * 40 : 100),
                  curve: _expanded ? Curves.easeOutBack : Curves.easeIn,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _SpeedDialDot(
                      color: colors[i].color,
                      onTap: () => widget.onColorSelected(colors[i]),
                    ),
                  ),
                ),

              // Select Sentence button — shown when expanded
              AnimatedScale(
                scale: _expanded ? 1.0 : 0.0,
                duration: Duration(
                  milliseconds:
                      _expanded ? 150 + (colors.length + 1) * 40 : 100,
                ),
                curve: _expanded ? Curves.easeOutBack : Curves.easeIn,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: Material(
                      elevation: 2,
                      shape: const CircleBorder(),
                      color: theme.colorScheme.primaryContainer,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: widget.onExpandToSentence,
                        child: Icon(
                          Icons.select_all,
                          size: 18,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Main FAB
              FloatingActionButton.small(
                heroTag: 'highlight_fab',
                onPressed: _toggle,
                tooltip: 'Highlight selection',
                child: const Icon(Icons.highlight),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpeedDialDot extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;

  const _SpeedDialDot({required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Material(
        elevation: 4,
        shape: const CircleBorder(),
        color: color,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
        ),
      ),
    );
  }
}
