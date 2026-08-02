import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/reader/data/reader_session_tracker.dart';

class _FakeStopwatch extends Stopwatch {
  int fakeElapsedMs = 0;

  @override
  int get elapsedMilliseconds => fakeElapsedMs;
}

void main() {
  late _FakeStopwatch stopwatch;
  late ReaderSessionTracker tracker;

  setUp(() {
    stopwatch = _FakeStopwatch();
    tracker = ReaderSessionTracker(bookFormat: 'epub', stopwatch: stopwatch);
  });

  test('produces a full summary of recorded activity', () {
    stopwatch.fakeElapsedMs = 90000;
    tracker.recordPageTurn();
    tracker.recordPageTurn();
    tracker.recordLookup(hit: true);
    tracker.recordLookup(hit: false);
    tracker.recordLookup(hit: true);
    tracker.recordWordSaved();
    tracker.recordSettingsChanged();
    tracker.recordCharactersRead(420);

    final summary = tracker.takeSummary(endReason: 'closed');

    expect(summary, {
      'duration_ms': 90000,
      'pages_turned': 2,
      'lookups': 3,
      'lookup_hits': 2,
      'words_saved': 1,
      'settings_changed': 1,
      'characters_read': 420,
      'book_format': 'epub',
      'end_reason': 'closed',
    });
  });

  test('accumulates characters read across calls', () {
    stopwatch.fakeElapsedMs = 5000;
    tracker.recordCharactersRead(300);
    tracker.recordCharactersRead(120);

    expect(tracker.takeSummary(endReason: 'closed')!['characters_read'], 420);
  });

  test('ignores non-positive character counts', () {
    stopwatch.fakeElapsedMs = 5000;
    tracker.recordCharactersRead(100);
    tracker.recordCharactersRead(0);
    tracker.recordCharactersRead(-50);

    expect(tracker.takeSummary(endReason: 'closed')!['characters_read'], 100);
  });

  test('keeps short sessions whose only activity is characters read', () {
    stopwatch.fakeElapsedMs = 10;
    tracker.recordCharactersRead(42);

    final summary = tracker.takeSummary(endReason: 'closed');

    expect(summary, isNotNull);
    expect(summary!['characters_read'], 42);
  });

  test('counts each distinct page once even when re-reported', () {
    stopwatch.fakeElapsedMs = 5000;
    // A re-layout (font size, margins, rotation) re-reports the same page.
    tracker.recordCharactersRead(600, pageKey: 'epubcfi(/6/4!/4/2)');
    tracker.recordCharactersRead(580, pageKey: 'epubcfi(/6/4!/4/2)');
    tracker.recordCharactersRead(590, pageKey: 'epubcfi(/6/4!/4/2)');

    expect(tracker.takeSummary(endReason: 'closed')!['characters_read'], 600);
  });

  test('counts pages with distinct keys separately', () {
    stopwatch.fakeElapsedMs = 5000;
    tracker.recordCharactersRead(600, pageKey: 'epubcfi(/6/4!/4/2)');
    tracker.recordCharactersRead(500, pageKey: 'epubcfi(/6/4!/4/8)');

    expect(tracker.takeSummary(endReason: 'closed')!['characters_read'], 1100);
  });

  test('counts a revisited page again after leaving it', () {
    stopwatch.fakeElapsedMs = 5000;
    tracker.recordCharactersRead(600, pageKey: 'epubcfi(/6/4!/4/2)');
    tracker.recordCharactersRead(500, pageKey: 'epubcfi(/6/4!/4/8)');
    tracker.recordCharactersRead(600, pageKey: 'epubcfi(/6/4!/4/2)');

    expect(tracker.takeSummary(endReason: 'closed')!['characters_read'], 1700);
  });

  test(
    'ignores non-positive keyed character counts without consuming the key',
    () {
      stopwatch.fakeElapsedMs = 5000;
      tracker.recordCharactersRead(0, pageKey: 'epubcfi(/6/4!/4/2)');
      tracker.recordCharactersRead(600, pageKey: 'epubcfi(/6/4!/4/2)');

      expect(tracker.takeSummary(endReason: 'closed')!['characters_read'], 600);
    },
  );

  test('taking a summary clears the last page key', () {
    stopwatch.fakeElapsedMs = 5000;
    tracker.recordCharactersRead(600, pageKey: 'epubcfi(/6/4!/4/2)');
    expect(tracker.takeSummary(endReason: 'backgrounded'), isNotNull);

    // The same page re-reports after resume (e.g. the webview redisplays);
    // the new session slice must count it, or a backgrounded round trip
    // would lose the page entirely.
    tracker.resume();
    stopwatch.fakeElapsedMs = 5000;
    tracker.recordCharactersRead(600, pageKey: 'epubcfi(/6/4!/4/2)');

    expect(tracker.takeSummary(endReason: 'closed')!['characters_read'], 600);
  });

  test('resets characters read after a summary is taken', () {
    stopwatch.fakeElapsedMs = 5000;
    tracker.recordCharactersRead(420);
    expect(tracker.takeSummary(endReason: 'backgrounded'), isNotNull);

    stopwatch.fakeElapsedMs = 5000;
    expect(tracker.takeSummary(endReason: 'closed')!['characters_read'], 0);
  });

  test('resets after a summary is taken', () {
    stopwatch.fakeElapsedMs = 5000;
    tracker.recordPageTurn();
    expect(tracker.takeSummary(endReason: 'backgrounded'), isNotNull);

    stopwatch.fakeElapsedMs = 0;
    expect(tracker.takeSummary(endReason: 'closed'), isNull);
  });

  test('drops short sessions with no activity', () {
    stopwatch.fakeElapsedMs = ReaderSessionTracker.minReportableMs - 1;
    expect(tracker.takeSummary(endReason: 'closed'), isNull);
  });

  test('keeps short sessions that had activity', () {
    stopwatch.fakeElapsedMs = 10;
    tracker.recordLookup(hit: false);

    final summary = tracker.takeSummary(endReason: 'closed');

    expect(summary, isNotNull);
    expect(summary!['lookups'], 1);
    expect(summary['lookup_hits'], 0);
  });

  test('resume restarts the clock after a backgrounded summary', () {
    stopwatch.fakeElapsedMs = 60000;
    expect(tracker.takeSummary(endReason: 'backgrounded'), isNotNull);
    expect(stopwatch.isRunning, isFalse);

    tracker.resume();

    expect(stopwatch.isRunning, isTrue);
    stopwatch.fakeElapsedMs = 30000;
    final summary = tracker.takeSummary(endReason: 'closed');
    expect(summary!['duration_ms'], 30000);
    expect(summary['end_reason'], 'closed');
  });
}
