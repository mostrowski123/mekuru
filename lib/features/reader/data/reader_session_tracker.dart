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

  /// Sessions shorter than this with no activity are dropped as noise (e.g.
  /// dispose firing right after a backgrounded summary was already taken).
  static const int minReportableMs = 1000;

  void recordPageTurn() => _pagesTurned++;

  void recordLookup({required bool hit}) {
    _lookups++;
    if (hit) _lookupHits++;
  }

  void recordWordSaved() => _wordsSaved++;

  void recordSettingsChanged() => _settingsChanged++;

  /// [count] is the approximate visible-character count of a displayed page;
  /// non-positive values (failed counts) are ignored.
  void recordCharactersRead(int count) {
    if (count > 0) _charactersRead += count;
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
