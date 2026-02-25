import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/library/presentation/providers/library_providers.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/presentation/providers/manga_reader_providers.dart';
import 'package:mekuru/features/manga/presentation/widgets/manga_page_view.dart';
import 'package:mekuru/features/reader/presentation/widgets/lookup_sheet.dart';

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

  // Word highlight state — shown while a lookup sheet is active
  MokuroWord? _highlightedWord;
  int? _highlightedPageIndex;

  @override
  void initState() {
    super.initState();
    // Restore last read page from book's lastReadCfi
    _currentPage = int.tryParse(widget.book.lastReadCfi ?? '') ?? 0;
    _pageController = PageController(initialPage: _currentPage);

    // Enter immersive mode
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
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
    ref.read(bookRepositoryProvider).updateProgress(
          widget.book.id,
          page.toString(),
          progress: progress,
        );
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
      _showBottomSheet(word, sentence, transparent)
          .then((_) => _clearHighlight());
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
      backgroundColor:
          transparent ? Colors.transparent : null,
      barrierColor: transparent
          ? Colors.black.withAlpha(30)
          : null,
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
      barrierColor: transparent
          ? Colors.black.withAlpha(30)
          : Colors.black54,
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

  void _handleTap(TapUpDetails details, int totalPages) {
    if (_isZoomed) return; // Don't navigate when zoomed

    final screenWidth = MediaQuery.of(context).size.width;
    final tapX = details.localPosition.dx;
    final normalizedX = tapX / screenWidth;

    final direction = ref.read(mangaReadingDirectionProvider);
    final isRtl = direction == MangaReadingDirection.rtl;

    // 25% left | 50% center | 25% right
    if (normalizedX < 0.25) {
      // Left zone
      if (isRtl) {
        _goToPage(_currentPage + 1, totalPages);
      } else {
        _goToPage(_currentPage - 1, totalPages);
      }
    } else if (normalizedX > 0.75) {
      // Right zone
      if (isRtl) {
        _goToPage(_currentPage - 1, totalPages);
      } else {
        _goToPage(_currentPage + 1, totalPages);
      }
    } else {
      // Center zone — toggle controls
      _toggleControls();
    }
  }

  void _showSettingsSheet(MokuroBook mokuroBook) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final direction = ref.watch(mangaReadingDirectionProvider);
          final transparent = ref.watch(mangaLookupTransparencyProvider);
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
                      ref
                          .read(mangaReadingDirectionProvider.notifier)
                          .toggle();
                    },
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

  @override
  Widget build(BuildContext context) {
    final pagesAsync = ref.watch(mangaPagesProvider(widget.book.id));
    final direction = ref.watch(mangaReadingDirectionProvider);

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
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: Colors.white),
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

          return Stack(
            children: [
              // Page content with tap zones
              GestureDetector(
                onTapUp: (details) => _handleTap(details, totalPages),
                child: PageView.builder(
                  controller: _pageController,
                  reverse: direction == MangaReadingDirection.rtl,
                  physics: _isZoomed
                      ? const NeverScrollableScrollPhysics()
                      : const ClampingScrollPhysics(),
                  itemCount: totalPages,
                  onPageChanged: (page) =>
                      _onPageChanged(page, totalPages),
                  itemBuilder: (context, index) {
                    final page = mokuroBook.pages[index];
                    return MangaPageView(
                      page: page,
                      imageDirPath: mokuroBook.imageDirPath,
                      debugOverlay: _debugOverlay,
                      highlightedWord:
                          index == _highlightedPageIndex
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
                            icon: const Icon(Icons.arrow_back,
                                color: Colors.white),
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
                            icon: const Icon(Icons.settings,
                                color: Colors.white),
                            onPressed: () =>
                                _showSettingsSheet(mokuroBook),
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
                        padding: const EdgeInsets.symmetric(horizontal: 16),
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
                                textDirection:
                                    direction == MangaReadingDirection.rtl
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
                                    _goToPage(value.round(), totalPages);
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
}
