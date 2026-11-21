import 'dart:async';

import 'package:mekuru/features/reader/data/models/epub_models.dart';

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

  /// Replaced by a newer viewer, or the reader closed.
  retired,
}

/// What the reader does when its current viewer reports in.
typedef ViewerReactions = ({
  void Function() loaded,
  void Function() locationsReady,
  void Function(EpubLocation location, {required bool trusted}) relocated,
  void Function(String description) failed,
  void Function() rendererGone,
});

/// One viewer's life, from the build that creates it to the one that
/// replaces it. The reader holds one session and swaps it whole for each new
/// viewer ([next]), so nothing known about a viewer outlives it, and the
/// viewer's callbacks are this session's methods: once it is retired, what
/// its viewer still sends reaches nothing.
class ViewerSession {
  /// The reader's first session, before it has built a viewer.
  ViewerSession.first(ViewerReactions reactions) : this._(0, reactions);

  ViewerSession._(this.epoch, this._reactions);

  /// Tells this viewer apart from the ones before and after it.
  final int epoch;
  final ViewerReactions _reactions;

  ViewerPhase _phase = ViewerPhase.loading;
  bool _locationsReady = false;
  bool _replacing = false;
  bool _stale = false;
  Timer? _watchdog;

  ViewerPhase get phase => _phase;

  /// The book has shown, and the viewer has not failed since. A dead
  /// renderer still counts until its replacement is built.
  bool get isLoaded =>
      _phase == ViewerPhase.ready || _phase == ViewerPhase.rendererGone;

  /// epub.js has locations: before them every page reports progress 0.
  bool get locationsReady => _locationsReady;

  /// A new viewer is being prepared to take this one's place.
  bool get isReplacing => _replacing;

  bool get _reports =>
      _phase == ViewerPhase.loading || _phase == ViewerPhase.ready;

  /// The session for the viewer that takes this one's place. This one is
  /// retired.
  ViewerSession next() {
    retire();
    return ViewerSession._(epoch + 1, _reactions);
  }

  void retire() {
    _watchdog?.cancel();
    _phase = ViewerPhase.retired;
  }

  /// Fails the load, and calls [onTimeout], when the book has not shown
  /// within [timeout].
  void startWatchdog(Duration timeout, void Function() onTimeout) {
    _watchdog?.cancel();
    _watchdog = Timer(timeout, () {
      _phase = ViewerPhase.failed;
      onTimeout();
    });
  }

  /// Starts replacing this viewer; false when it never showed the book or a
  /// replacement is already on its way.
  bool beginReplacement() {
    if (_replacing || !isLoaded) return false;
    return _replacing = true;
  }

  /// Settings changed while a screen covered the reader: replace this viewer
  /// when the reader shows again.
  void markStale() => _stale = true;

  /// Whether this viewer went stale under a covering screen; true only once.
  bool takeStale() {
    final stale = _stale;
    _stale = false;
    return stale;
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

  void loadFailed(String description) {
    if (_phase != ViewerPhase.retired) _fail(description);
  }

  /// A book that showed gets a new viewer; one still opening fails, so a
  /// book that kills the renderer cannot loop.
  void rendererDied() {
    switch (_phase) {
      case ViewerPhase.loading:
        _fail('The web view stopped.');
      case ViewerPhase.ready:
        _phase = ViewerPhase.rendererGone;
        _reactions.rendererGone();
      case ViewerPhase.rendererGone:
      case ViewerPhase.failed:
      case ViewerPhase.retired:
    }
  }

  void _fail(String description) {
    _watchdog?.cancel();
    _phase = ViewerPhase.failed;
    _reactions.failed(description);
  }
}
