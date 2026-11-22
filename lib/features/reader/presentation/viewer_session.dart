import 'dart:async';

import 'package:mekuru/features/reader/data/models/epub_models.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';

/// Where one EPUB viewer is in its life.
enum ViewerPhase {
  /// Built; the page has not shown the book yet.
  loading,

  /// The book shows.
  ready,

  /// The renderer died after the book showed; a new viewer must replace it.
  rendererGone,

  /// The book could not be shown: a load error, or the load timed out.
  failed,

  /// Replaced by a newer viewer, or the reader closed or opens the book
  /// again.
  retired,
}

/// The reading mode a viewer is built for. The page is laid out for it
/// once, so a change to any of it needs a new viewer.
typedef ViewerLayout = ({
  ReaderDirection readingDirection,
  bool verticalText,
  bool splitVerticalText,
  bool scrollView,
});

/// The layout [settings] ask for.
ViewerLayout viewerLayoutOf(ReaderSettings settings) => (
  readingDirection: settings.readingDirection,
  verticalText: settings.verticalText,
  splitVerticalText: settings.splitVerticalText,
  scrollView: settings.scrollView,
);

/// What the reader does when its current viewer reports in. [failed] gets
/// the load error (the page's own description of it, or the exception
/// reading the book's file), or null when the web view stopped before the
/// book showed.
typedef ViewerReactions = ({
  void Function() loaded,
  void Function() locationsReady,
  void Function(EpubLocation location, {required bool trusted}) relocated,
  void Function(Object? error) failed,
  void Function() timedOut,
  void Function() rendererGone,
});

/// One viewer's life, from the build that creates it to the one that
/// replaces it. The reader holds one session per viewer and swaps it whole
/// for each new viewer, so nothing known about a viewer outlives it, and the
/// viewer's callbacks are this session's methods: once it is retired, what
/// its viewer still sends reaches nothing.
class ViewerSession {
  /// A new viewer for [layout]. It has [loadTimeout] of drawn frames to show
  /// the book, or the load fails ([ViewerReactions.timedOut]).
  /// [framesDrawn]: whether frames are drawn now (see [framesChanged]).
  ViewerSession(
    this.layout,
    this._reactions, {
    required Duration loadTimeout,
    required bool framesDrawn,
  }) : _loadTimeout = loadTimeout {
    framesChanged(drawn: framesDrawn);
  }

  /// The reading mode this viewer lays the book out in.
  final ViewerLayout layout;
  final ViewerReactions _reactions;
  final Duration _loadTimeout;

  // Runs only while loading with frames drawn: showing the book, failing,
  // retiring and the app going away stop it.
  Timer? _watchdog;
  bool _framesDrawn = false;
  ViewerPhase _phase = ViewerPhase.loading;
  bool _locationsReady = false;
  bool _replacing = false;

  ViewerPhase get phase => _phase;

  /// The book has shown, and the viewer has not failed since. A dead
  /// renderer still counts until its replacement is built.
  bool get isLoaded =>
      _phase == ViewerPhase.ready || _phase == ViewerPhase.rendererGone;

  /// epub.js has locations: before them every page reports progress 0.
  bool get locationsReady => _locationsReady;

  /// A new viewer is being prepared to take this one's place.
  bool get isReplacing => _replacing;

  /// The book's highlights are drawn on this viewer's page.
  bool highlightsRestored = false;

  bool get _reports =>
      _phase == ViewerPhase.loading || _phase == ViewerPhase.ready;

  void retire() {
    _watchdog?.cancel();
    _phase = ViewerPhase.retired;
  }

  /// Frames are drawn, or no longer are (the app went away). The page
  /// cannot load without them, so the load is timed only while they are;
  /// each return gives it its whole load timeout again.
  void framesChanged({required bool drawn}) {
    if (drawn == _framesDrawn) return;
    _framesDrawn = drawn;
    _watchdog?.cancel();
    if (!drawn || _phase != ViewerPhase.loading) return;
    _watchdog = Timer(_loadTimeout, () {
      _phase = ViewerPhase.failed;
      _reactions.timedOut();
    });
  }

  /// Starts replacing this viewer when it no longer serves: its renderer
  /// died, or it shows, or failed to show, a layout other than [wanted]. A
  /// viewer still loading is judged once it loads or fails. False when it
  /// still serves or a replacement is already on its way.
  bool beginReplacement(ViewerLayout wanted) {
    if (_replacing) return false;
    return _replacing = switch (_phase) {
      ViewerPhase.rendererGone => true,
      ViewerPhase.ready || ViewerPhase.failed => wanted != layout,
      ViewerPhase.loading || ViewerPhase.retired => false,
    };
  }

  // ── The viewer's callbacks ───────────────────────────────────────────

  /// The page shows the book; epub.js says so again after every display.
  void loaded() {
    if (_phase == ViewerPhase.loading) {
      _watchdog?.cancel();
      _phase = ViewerPhase.ready;
    }
    if (_phase == ViewerPhase.ready) _reactions.loaded();
  }

  /// Can come before [loaded] when the locations were cached.
  void locationsArrived() {
    if (!_reports) return;
    _locationsReady = true;
    _reactions.locationsReady();
  }

  /// The page moved; its progress is trusted only once locations exist.
  void relocated(EpubLocation location) {
    if (!_reports) return;
    _reactions.relocated(location, trusted: _locationsReady);
  }

  void loadFailed(Object error) {
    if (_phase != ViewerPhase.retired) _fail(error);
  }

  /// A book that showed gets a new viewer; one still opening fails, so a
  /// book that kills the renderer cannot loop.
  void rendererDied() {
    switch (_phase) {
      case ViewerPhase.loading:
        _fail(null);
      case ViewerPhase.ready:
        _phase = ViewerPhase.rendererGone;
        _reactions.rendererGone();
      case ViewerPhase.rendererGone:
      case ViewerPhase.failed:
      case ViewerPhase.retired:
    }
  }

  void _fail(Object? error) {
    _watchdog?.cancel();
    _phase = ViewerPhase.failed;
    _reactions.failed(error);
  }
}
