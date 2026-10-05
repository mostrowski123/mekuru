// Pure Dart — no Flutter imports, so this stays unit-testable.
//
// Every window here is *trailing* and keyed on the LOCAL calendar date derived
// from `startedAt`/`createdAt`. Day arithmetic goes through DateTime(y, m, d),
// never Duration(hours: 24), so it stays correct across DST transitions on
// devices outside Japan.
import 'package:mekuru/core/database/database_provider.dart';

/// The time window a chart covers.
enum StatsPeriod {
  /// 7 day buckets ending today.
  week,

  /// 30 day buckets ending today.
  month,

  /// 12 calendar-month buckets ending with the current month.
  year,

  /// Month buckets from the first session through the current month.
  all,
}

/// Which book format a chart is restricted to.
enum StatsFormat { all, epub, manga }

/// One aggregated bar: a day (week/month) or a calendar month (year/all).
class StatBucket {
  const StatBucket({
    required this.start,
    required this.durationMs,
    required this.charactersRead,
    required this.pagesTurned,
    required this.lookups,
  });

  /// Local midnight of the day, or the first of the month for month buckets.
  final DateTime start;
  final int durationMs;
  final int charactersRead;
  final int pagesTurned;
  final int lookups;

  @override
  String toString() =>
      'StatBucket($start, durationMs: $durationMs, '
      'charactersRead: $charactersRead, pagesTurned: $pagesTurned, '
      'lookups: $lookups)';

  @override
  bool operator ==(Object other) =>
      other is StatBucket &&
      other.start == start &&
      other.durationMs == durationMs &&
      other.charactersRead == charactersRead &&
      other.pagesTurned == pagesTurned &&
      other.lookups == lookups;

  @override
  int get hashCode =>
      Object.hash(start, durationMs, charactersRead, pagesTurned, lookups);
}

/// One cell of the year heatmap.
class HeatmapDay {
  const HeatmapDay({
    required this.day,
    required this.minutes,
    required this.charactersRead,
    required this.lookups,
  });

  /// Local midnight of the day.
  final DateTime day;

  /// Whole minutes read, floored from the day's summed milliseconds. A day can
  /// therefore read 0 minutes while still having characters or lookups, so
  /// treat a day as active when *any* of the three is non-zero.
  final int minutes;
  final int charactersRead;
  final int lookups;

  @override
  String toString() =>
      'HeatmapDay($day, minutes: $minutes, '
      'charactersRead: $charactersRead, lookups: $lookups)';

  @override
  bool operator ==(Object other) =>
      other is HeatmapDay &&
      other.day == day &&
      other.minutes == minutes &&
      other.charactersRead == charactersRead &&
      other.lookups == lookups;

  @override
  int get hashCode => Object.hash(day, minutes, charactersRead, lookups);
}

/// One step of the running unique-vocabulary curve.
class CumulativePoint {
  const CumulativePoint({required this.day, required this.total});

  /// Local midnight of the day the total changed on.
  final DateTime day;

  /// Running count of distinct expressions seen up to the end of [day].
  final int total;

  @override
  String toString() => 'CumulativePoint($day, total: $total)';

  @override
  bool operator ==(Object other) =>
      other is CumulativePoint && other.day == day && other.total == total;

  @override
  int get hashCode => Object.hash(day, total);
}

/// Keeps only the sessions matching [format]; [StatsFormat.all] keeps
/// everything, including rows with an unrecognised `bookFormat`.
List<ReadingSession> filterSessions(
  List<ReadingSession> sessions,
  StatsFormat format,
) {
  final wanted = _formatName(format);
  if (wanted == null) return [...sessions];
  return sessions.where((s) => s.bookFormat == wanted).toList();
}

/// Keeps only the word events matching [format]. `'other'` rows (saves made
/// outside a reader) therefore surface under [StatsFormat.all] only.
List<WordEvent> filterWordEvents(List<WordEvent> events, StatsFormat format) {
  final wanted = _formatName(format);
  if (wanted == null) return [...events];
  return events.where((e) => e.source == wanted).toList();
}

/// Aggregates [sessions] into the trailing buckets of [period], relative to
/// [now].
///
/// Empty buckets are present with zeros, so the result is always a dense,
/// chronologically ascending series. [StatsPeriod.all] spans the first
/// session's month through the current month; with no usable session it
/// degrades to a single zeroed current-month bucket, so callers never have to
/// handle an empty series.
List<StatBucket> bucketize(
  List<ReadingSession> sessions,
  StatsPeriod period,
  DateTime now,
) {
  final grid = _grid(sessions, period, now);
  final totals = _totalsByKey(sessions, grid.starts, grid.keyOf);
  return [
    for (final MapEntry(key: start, value: total) in totals.entries)
      total.toBucket(start),
  ];
}

/// The trailing 365 days ending today, oldest first, with empty days zeroed.
List<HeatmapDay> heatmapDays(List<ReadingSession> sessions, DateTime now) {
  final totals = _totalsByKey(sessions, _dayStarts(_dayKey(now), 365), _dayKey);
  return [
    for (final MapEntry(key: day, value: total) in totals.entries)
      HeatmapDay(
        day: day,
        minutes: total.durationMs ~/ Duration.millisecondsPerMinute,
        charactersRead: total.charactersRead,
        lookups: total.lookups,
      ),
  ];
}

/// Dictionary lookups per 1000 characters read, or null when the bucket has no
/// characters to divide by.
double? lookupRatePer1k(StatBucket bucket) {
  if (bucket.charactersRead == 0) return null;
  return bucket.lookups * 1000 / bucket.charactersRead;
}

/// The running count of distinct expressions over time.
///
/// Each expression counts once, on the day of its *first* event, whatever the
/// event's kind — an expression saved in-app and later sent to AnkiDroid is one
/// word, not two. One point is emitted per day on which the total changed,
/// carrying that day's end-of-day total; days that only repeat known
/// expressions are omitted.
List<CumulativePoint> cumulativeUniqueWords(List<WordEvent> events) {
  final seen = <String>{};
  // Insertion-ordered, and the input is sorted, so days come out chronological;
  // re-assigning a day keeps its end-of-day total.
  final totalByDay = <DateTime, int>{};
  var total = 0;

  for (final event in _sortedByCreatedAt(events)) {
    if (seen.add(event.expression)) {
      totalByDay[_dayKey(event.createdAt)] = ++total;
    }
  }

  return [
    for (final MapEntry(key: day, value: runningTotal) in totalByDay.entries)
      CumulativePoint(day: day, total: runningTotal),
  ];
}

/// The all-time day with the highest total reading duration, aggregated the
/// same way as a [bucketize] day bucket.
///
/// Unlike [bucketize] this has no trailing window — [now] only bounds the
/// future, so days dated after today (clock changes) are ignored. Ties go to
/// the earliest day. Returns null when no session falls on or before today.
StatBucket? bestDay(List<ReadingSession> sessions, DateTime now) {
  final today = _dayKey(now);
  final totals = <DateTime, _Totals>{};

  for (final session in sessions) {
    final day = _dayKey(session.startedAt);
    if (day.isAfter(today)) continue;
    (totals[day] ??= _Totals()).add(session);
  }
  if (totals.isEmpty) return null;

  // Map order follows input order, not chronology, so the tie rule is explicit
  // rather than implied by the scan.
  var best = totals.entries.first;
  for (final entry in totals.entries) {
    final isBetter = entry.value.durationMs > best.value.durationMs;
    final isEarlierTie =
        entry.value.durationMs == best.value.durationMs &&
        entry.key.isBefore(best.key);
    if (isBetter || isEarlierTie) best = entry;
  }

  return best.value.toBucket(best.key);
}

/// The numbers behind the three hero tiles.
class PeriodTotals {
  const PeriodTotals({
    required this.durationMs,
    required this.charactersRead,
    required this.wordsAdded,
  });

  final int durationMs;
  final int charactersRead;
  final int wordsAdded;
}

/// The headline totals for one period-and-format selection.
///
/// Summed off the same bucket grid the charts are drawn from, so a tile and
/// the chart under it can never disagree about what the window contains.
PeriodTotals periodTotals({
  required List<ReadingSession> sessions,
  required List<WordEvent> events,
  required StatsPeriod period,
  required DateTime now,
}) {
  final buckets = bucketize(sessions, period, now);
  var durationMs = 0;
  var charactersRead = 0;
  for (final bucket in buckets) {
    durationMs += bucket.durationMs;
    charactersRead += bucket.charactersRead;
  }
  return PeriodTotals(
    durationMs: durationMs,
    charactersRead: charactersRead,
    wordsAdded: wordsAddedSince(events, windowStart(buckets, period)),
  );
}

/// The first instant [period] covers, or null when it has no lower bound.
///
/// Read off the bucket grid rather than recomputed, so the tiles can never
/// drift out of step with the aggregator's trailing-window arithmetic.
/// [StatsPeriod.all] is the exception: its grid starts at the first *session*'s
/// month, which would drop words saved outside a reader before any session
/// existed — including every row the migration backfilled.
DateTime? windowStart(List<StatBucket> buckets, StatsPeriod period) {
  if (period == StatsPeriod.all || buckets.isEmpty) return null;
  return buckets.first.start;
}

/// Distinct expressions first seen on or after [start] — all of them when
/// [start] is null.
///
/// Derived from the cumulative curve rather than counted directly, so this tile
/// and the vocab-growth chart agree to the word: both credit an expression once,
/// on the day of its first event, whatever the event's kind.
int wordsAddedSince(List<WordEvent> events, DateTime? start) {
  final points = cumulativeUniqueWords(events);
  if (points.isEmpty) return 0;

  final total = points.last.total;
  if (start == null) return total;

  // Points ascend chronologically, so the last one before the window carries
  // the running total the window started from.
  var before = 0;
  for (final point in points) {
    if (!point.day.isBefore(start)) break;
    before = point.total;
  }
  return total - before;
}

// ---------------------------------------------------------------------------
// Internals
// ---------------------------------------------------------------------------

/// Running totals for one bucket. Clamps negative counters to 0 so a row
/// corrupted by a clock change (or a bad write) skews nothing.
class _Totals {
  int durationMs = 0;
  int charactersRead = 0;
  int pagesTurned = 0;
  int lookups = 0;

  void add(ReadingSession session) {
    durationMs += _atLeastZero(session.durationMs);
    charactersRead += _atLeastZero(session.charactersRead);
    pagesTurned += _atLeastZero(session.pagesTurned);
    lookups += _atLeastZero(session.lookups);
  }

  StatBucket toBucket(DateTime start) => StatBucket(
    start: start,
    durationMs: durationMs,
    charactersRead: charactersRead,
    pagesTurned: pagesTurned,
    lookups: lookups,
  );
}

int _atLeastZero(int value) => value < 0 ? 0 : value;

String? _formatName(StatsFormat format) => switch (format) {
  StatsFormat.all => null,
  StatsFormat.epub => 'epub',
  StatsFormat.manga => 'manga',
};

/// The bucket starts of a period paired with the key function that maps a
/// session onto them. Both halves come from one exhaustive switch, so a period
/// can never have a start list without the matching granularity — mismatched,
/// every bucket would silently read zero.
typedef _Grid = ({List<DateTime> starts, DateTime Function(DateTime) keyOf});

_Grid _grid(List<ReadingSession> sessions, StatsPeriod period, DateTime now) =>
    switch (period) {
      StatsPeriod.week => (starts: _dayStarts(_dayKey(now), 7), keyOf: _dayKey),
      StatsPeriod.month => (
        starts: _dayStarts(_dayKey(now), 30),
        keyOf: _dayKey,
      ),
      StatsPeriod.year => (
        starts: _monthStarts(_monthKey(now), 12),
        keyOf: _monthKey,
      ),
      StatsPeriod.all => (
        starts: _allMonthStarts(sessions, _monthKey(now)),
        keyOf: _monthKey,
      ),
    };

/// One [_Totals] per entry in [starts], in the same order.
///
/// A session whose key has no bucket is outside the window — before it, or
/// dated in the future by a clock change — and is dropped. This is the single
/// place that rule is enforced.
Map<DateTime, _Totals> _totalsByKey(
  List<ReadingSession> sessions,
  List<DateTime> starts,
  DateTime Function(DateTime) keyOf,
) {
  final totals = {for (final start in starts) start: _Totals()};
  for (final session in sessions) {
    totals[keyOf(session.startedAt)]?.add(session);
  }
  return totals;
}

/// Local midnight of [moment]'s calendar day.
DateTime _dayKey(DateTime moment) =>
    DateTime(moment.year, moment.month, moment.day);

/// Local midnight of the first of [moment]'s calendar month.
DateTime _monthKey(DateTime moment) => DateTime(moment.year, moment.month);

/// [count] consecutive day starts ending on [last], oldest first.
List<DateTime> _dayStarts(DateTime last, int count) {
  // Hoisted: these are native calendar getters, not fields.
  final year = last.year;
  final month = last.month;
  final day = last.day;
  return [
    for (var offset = count - 1; offset >= 0; offset--)
      DateTime(year, month, day - offset),
  ];
}

/// [count] consecutive month starts ending on [last], oldest first.
List<DateTime> _monthStarts(DateTime last, int count) {
  final year = last.year;
  final month = last.month;
  return [
    for (var offset = count - 1; offset >= 0; offset--)
      DateTime(year, month - offset),
  ];
}

/// Month starts from the earliest session through [thisMonth].
///
/// Starting at [thisMonth] and only ever moving backwards means "no sessions"
/// and "every session is dated in the future" both fall out as a single
/// current-month bucket, with no special case.
List<DateTime> _allMonthStarts(
  List<ReadingSession> sessions,
  DateTime thisMonth,
) {
  // Min over the raw instants first — isBefore is an integer compare — so only
  // one month key is built, instead of one per session.
  DateTime? earliest;
  for (final session in sessions) {
    if (earliest == null || session.startedAt.isBefore(earliest)) {
      earliest = session.startedAt;
    }
  }

  var first = thisMonth;
  if (earliest != null) {
    final month = _monthKey(earliest);
    if (month.isBefore(first)) first = month;
  }

  final count =
      (thisMonth.year - first.year) * 12 + (thisMonth.month - first.month) + 1;
  return _monthStarts(thisMonth, count);
}

/// Sorted by `createdAt` ascending, without touching the caller's list.
///
/// Production rows already arrive ascending from
/// `StatsRepository.watchAllWordEvents`, so this is defensive: it keeps this
/// function's contract independent of caller ordering. Ties need no stable
/// sort — events sharing an instant share a day, so their relative order
/// cannot change the emitted points.
List<WordEvent> _sortedByCreatedAt(List<WordEvent> events) =>
    [...events]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
