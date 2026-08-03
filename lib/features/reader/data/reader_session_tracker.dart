/// Accumulates per-session reading activity for the `session.summary` usage
/// log. Pure Dart (no Flutter imports) so it stays unit-testable.
///
/// Lifecycle: create when the reader opens, record activity as it happens,
/// call [takeSummary] when the reader closes (`end_reason: closed`) or the app
/// goes to background (`end_reason: backgrounded`), and [resume] when the app
/// returns to the foreground. [takeSummary] resets the tracker, so a
/// background/foreground round trip produces two summaries whose durations
/// add up to the real total.
class ReaderSessionTracker {
  ReaderSessionTracker({required this.bookFormat, Stopwatch? stopwatch})
    : _stopwatch = stopwatch ?? Stopwatch() {
    _stopwatch.start();
  }

  /// 'epub' or 'manga'.
  final String bookFormat;

  final Stopwatch _stopwatch;

  int _pagesTurned = 0;
  int _lookups = 0;
  int _lookupHits = 0;
  int _wordsSaved = 0;
  int _settingsChanged = 0;
  int _charactersRead = 0;

  // A keyed page waiting out its dwell; see [recordCharactersRead].
  ({String key, int chars, int sinceMs})? _pendingPage;

  /// Sessions shorter than this with no activity are dropped as noise (e.g.
  /// dispose firing right after a backgrounded summary was already taken).
  static const int minReportableMs = 1000;

  /// How long a keyed page must stay on screen before its characters count
  /// as read. Pages left sooner (slider seeks, rapid jumps) are dropped.
  static const int pageDwellMs = 3000;

  void recordPageTurn() => _pagesTurned++;

  void recordLookup({required bool hit}) {
    _lookups++;
    if (hit) _lookupHits++;
  }

  void recordWordSaved() => _wordsSaved++;

  void recordSettingsChanged() => _settingsChanged++;

  /// [count] is the approximate visible-character count of a displayed page.
  ///
  /// A non-null [pageKey] — an opaque identity for what is on screen, e.g. a
  /// start CFI or page index — makes the page *pending* instead of counting
  /// immediately: its characters count only once the page has stayed on
  /// screen for [pageDwellMs], committed when a different key is reported or
  /// the summary is taken. Re-reports of the pending key (re-layouts: font
  /// size, margins, rotation) keep the original dwell start and never double
  /// count; a page revisited after leaving it counts again.
  ///
  /// Pass null only when the page has no usable identity (e.g. the EPUB
  /// bridge failed to produce a start CFI); the count is then added
  /// immediately, with non-positive counts ignored.
  void recordCharactersRead(int count, {String? pageKey}) {
    final chars = count > 0 ? count : 0;
    if (pageKey == null) {
      _charactersRead += chars;
      return;
    }
    final pending = _pendingPage;
    if (pending != null && pageKey == pending.key) {
      // Re-layout of the page already on screen. A count that failed on the
      // first report (0) may be filled in by the re-report.
      if (pending.chars == 0) {
        _pendingPage = (
          key: pending.key,
          chars: chars,
          sinceMs: pending.sinceMs,
        );
      }
      return;
    }
    _commitPendingPage();
    _pendingPage = (
      key: pageKey,
      chars: chars,
      sinceMs: _stopwatch.elapsedMilliseconds,
    );
  }

  /// Counts the pending page if it stayed on screen for [pageDwellMs];
  /// pages left sooner were skimmed past, not read, and are dropped.
  void _commitPendingPage() {
    final pending = _pendingPage;
    if (pending == null) return;
    if (_stopwatch.elapsedMilliseconds - pending.sinceMs >= pageDwellMs) {
      _charactersRead += pending.chars;
    }
    _pendingPage = null;
  }

  bool get _hasActivity =>
      _pagesTurned > 0 ||
      _lookups > 0 ||
      _wordsSaved > 0 ||
      _settingsChanged > 0 ||
      _charactersRead > 0;

  /// Restarts the clock after a backgrounded summary was taken.
  void resume() {
    if (!_stopwatch.isRunning) _stopwatch.start();
  }

  /// Returns the summary attributes for this session slice and resets the
  /// tracker, or null when there is nothing worth reporting.
  ///
  /// [endReason] is 'closed' or 'backgrounded'. Attribute values are counts
  /// and enums only — nothing book- or user-identifying.
  Map<String, Object>? takeSummary({required String endReason}) {
    _commitPendingPage();
    final durationMs = _stopwatch.elapsedMilliseconds;
    if (durationMs < minReportableMs && !_hasActivity) return null;

    final summary = <String, Object>{
      'duration_ms': durationMs,
      'pages_turned': _pagesTurned,
      'lookups': _lookups,
      'lookup_hits': _lookupHits,
      'words_saved': _wordsSaved,
      'settings_changed': _settingsChanged,
      'characters_read': _charactersRead,
      'book_format': bookFormat,
      'end_reason': endReason,
    };

    _stopwatch
      ..stop()
      ..reset();
    _pagesTurned = 0;
    _lookups = 0;
    _lookupHits = 0;
    _wordsSaved = 0;
    _settingsChanged = 0;
    _charactersRead = 0;

    return summary;
  }
}
