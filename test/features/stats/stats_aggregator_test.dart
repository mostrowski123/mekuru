import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/stats/data/services/stats_aggregator.dart';
import 'package:path/path.dart' as p;

// bookId and wordsSaved are fixed: the aggregator reads neither, so exposing
// them as knobs would imply it cares about book identity or saved-word counts.
ReadingSession _session({
  int id = 0,
  String bookFormat = 'epub',
  required DateTime startedAt,
  int durationMs = 0,
  int pagesTurned = 0,
  int charactersRead = 0,
  int lookups = 0,
}) => ReadingSession(
  id: id,
  bookId: null,
  bookFormat: bookFormat,
  startedAt: startedAt,
  durationMs: durationMs,
  pagesTurned: pagesTurned,
  charactersRead: charactersRead,
  lookups: lookups,
  wordsSaved: 0,
);

WordEvent _event({
  int id = 0,
  String kind = 'saved',
  required String expression,
  String source = 'epub',
  required DateTime createdAt,
}) => WordEvent(
  id: id,
  kind: kind,
  expression: expression,
  source: source,
  createdAt: createdAt,
);

void main() {
  // Fixed "now" so every window is deterministic: today is Sunday 2026-02-15.
  final now = DateTime(2026, 2, 15, 10, 30);

  group('purity', () {
    test('stats_aggregator.dart imports no Flutter libraries', () {
      final source = File(
        p.join(
          'lib',
          'features',
          'stats',
          'data',
          'services',
          'stats_aggregator.dart',
        ),
      ).readAsStringSync();
      final imports = RegExp(
        r"^import '([^']+)';",
        multiLine: true,
      ).allMatches(source).map((m) => m.group(1)!).toList();

      // Allowlist, not a denylist: anything new has to justify itself, so
      // dart:ui or a relative import of a widget file fails too.
      expect(imports, isNotEmpty);
      for (final import in imports) {
        final isAllowed =
            import == 'package:mekuru/core/database/database_provider.dart' ||
            (import.startsWith('dart:') && import != 'dart:ui');
        expect(
          isAllowed,
          isTrue,
          reason:
              'stats_aggregator.dart must stay Flutter-free, but imports '
              '$import',
        );
      }
    });
  });

  group('value equality', () {
    test('StatBucket compares by value', () {
      final a = StatBucket(
        start: DateTime(2026, 2, 15),
        durationMs: 1,
        charactersRead: 2,
        pagesTurned: 3,
        lookups: 4,
      );
      final same = StatBucket(
        start: DateTime(2026, 2, 15),
        durationMs: 1,
        charactersRead: 2,
        pagesTurned: 3,
        lookups: 4,
      );
      final differentDay = StatBucket(
        start: DateTime(2026, 2, 16),
        durationMs: 1,
        charactersRead: 2,
        pagesTurned: 3,
        lookups: 4,
      );

      expect(a, same);
      expect(a.hashCode, same.hashCode);
      expect(a, isNot(differentDay));
    });

    test('HeatmapDay compares by value', () {
      final a = HeatmapDay(
        day: DateTime(2026, 2, 15),
        minutes: 5,
        charactersRead: 10,
        lookups: 1,
      );
      final same = HeatmapDay(
        day: DateTime(2026, 2, 15),
        minutes: 5,
        charactersRead: 10,
        lookups: 1,
      );
      final differentMinutes = HeatmapDay(
        day: DateTime(2026, 2, 15),
        minutes: 6,
        charactersRead: 10,
        lookups: 1,
      );

      expect(a, same);
      expect(a.hashCode, same.hashCode);
      expect(a, isNot(differentMinutes));
    });

    test('CumulativePoint compares by value', () {
      final a = CumulativePoint(day: DateTime(2026, 2, 15), total: 3);
      final same = CumulativePoint(day: DateTime(2026, 2, 15), total: 3);
      final differentTotal = CumulativePoint(
        day: DateTime(2026, 2, 15),
        total: 4,
      );

      expect(a, same);
      expect(a.hashCode, same.hashCode);
      expect(a, isNot(differentTotal));
    });

    test('aggregated results compare by value, so lists can be matched', () {
      expect(
        bucketize(const [], StatsPeriod.week, now).last,
        StatBucket(
          start: DateTime(2026, 2, 15),
          durationMs: 0,
          charactersRead: 0,
          pagesTurned: 0,
          lookups: 0,
        ),
      );
    });
  });

  group('filterSessions', () {
    final epub = _session(id: 1, bookFormat: 'epub', startedAt: now);
    final manga = _session(id: 2, bookFormat: 'manga', startedAt: now);
    final unknown = _session(id: 3, bookFormat: 'pdf', startedAt: now);
    final sessions = [epub, manga, unknown];

    test('all keeps every session, including unknown formats', () {
      expect(filterSessions(sessions, StatsFormat.all), sessions);
    });

    test('epub keeps only epub sessions', () {
      expect(filterSessions(sessions, StatsFormat.epub), [epub]);
    });

    test('manga keeps only manga sessions', () {
      expect(filterSessions(sessions, StatsFormat.manga), [manga]);
    });

    test('preserves input order', () {
      final ordered = [
        _session(id: 1, startedAt: DateTime(2026, 2, 3)),
        _session(id: 2, startedAt: DateTime(2026, 2, 1)),
        _session(id: 3, startedAt: DateTime(2026, 2, 2)),
      ];

      expect(filterSessions(ordered, StatsFormat.epub).map((s) => s.id), [
        1,
        2,
        3,
      ]);
    });

    test('does not mutate the input list', () {
      final input = [...sessions];
      filterSessions(input, StatsFormat.epub);
      expect(input, sessions);
    });
  });

  group('filterWordEvents', () {
    final epub = _event(id: 1, expression: '猫', source: 'epub', createdAt: now);
    final manga = _event(
      id: 2,
      expression: '犬',
      source: 'manga',
      createdAt: now,
    );
    final other = _event(
      id: 3,
      expression: '鳥',
      source: 'other',
      createdAt: now,
    );
    final events = [epub, manga, other];

    test('all keeps every event, including other-source rows', () {
      expect(filterWordEvents(events, StatsFormat.all), events);
    });

    test('epub drops manga and other rows', () {
      expect(filterWordEvents(events, StatsFormat.epub), [epub]);
    });

    test('manga drops epub and other rows', () {
      expect(filterWordEvents(events, StatsFormat.manga), [manga]);
    });
  });

  group('bucketize week', () {
    test(
      'returns 7 day buckets ending today, zeroed when there is no data',
      () {
        final buckets = bucketize(const [], StatsPeriod.week, now);

        expect(buckets, hasLength(7));
        expect(buckets.first.start, DateTime(2026, 2, 9));
        expect(buckets.last.start, DateTime(2026, 2, 15));
        for (final bucket in buckets) {
          expect(bucket.durationMs, 0);
          expect(bucket.charactersRead, 0);
          expect(bucket.pagesTurned, 0);
          expect(bucket.lookups, 0);
        }
      },
    );

    test('bucket starts are consecutive local midnights', () {
      final buckets = bucketize(const [], StatsPeriod.week, now);

      expect(buckets.map((b) => b.start), [
        DateTime(2026, 2, 9),
        DateTime(2026, 2, 10),
        DateTime(2026, 2, 11),
        DateTime(2026, 2, 12),
        DateTime(2026, 2, 13),
        DateTime(2026, 2, 14),
        DateTime(2026, 2, 15),
      ]);
    });

    test('23:59 and 00:01 land in adjacent day buckets', () {
      final buckets = bucketize(
        [
          _session(
            id: 1,
            startedAt: DateTime(2026, 2, 10, 23, 59),
            durationMs: 1000,
          ),
          _session(
            id: 2,
            startedAt: DateTime(2026, 2, 11, 0, 1),
            durationMs: 2000,
          ),
        ],
        StatsPeriod.week,
        now,
      );

      expect(buckets[1].start, DateTime(2026, 2, 10));
      expect(buckets[1].durationMs, 1000);
      expect(buckets[2].start, DateTime(2026, 2, 11));
      expect(buckets[2].durationMs, 2000);
    });

    test('day 7 is inside the window and day 8 is outside', () {
      final buckets = bucketize(
        [
          _session(id: 1, startedAt: DateTime(2026, 2, 9), durationMs: 5000),
          _session(
            id: 2,
            startedAt: DateTime(2026, 2, 8, 23, 59),
            durationMs: 9000,
          ),
        ],
        StatsPeriod.week,
        now,
      );

      expect(buckets.first.durationMs, 5000);
      expect(buckets.fold<int>(0, (sum, b) => sum + b.durationMs), 5000);
    });

    test('sessions dated after today are dropped', () {
      final buckets = bucketize(
        [
          _session(
            id: 1,
            startedAt: DateTime(2026, 2, 16, 0, 1),
            durationMs: 60000,
            charactersRead: 100,
          ),
        ],
        StatsPeriod.week,
        now,
      );

      expect(buckets.fold<int>(0, (sum, b) => sum + b.durationMs), 0);
      expect(buckets.fold<int>(0, (sum, b) => sum + b.charactersRead), 0);
    });

    test('sums every metric of same-day sessions', () {
      final buckets = bucketize(
        [
          _session(
            id: 1,
            startedAt: DateTime(2026, 2, 12, 8),
            durationMs: 60000,
            pagesTurned: 3,
            charactersRead: 900,
            lookups: 4,
          ),
          _session(
            id: 2,
            startedAt: DateTime(2026, 2, 12, 22),
            durationMs: 30000,
            pagesTurned: 2,
            charactersRead: 100,
            lookups: 1,
          ),
        ],
        StatsPeriod.week,
        now,
      );

      final bucket = buckets[3];
      expect(bucket.start, DateTime(2026, 2, 12));
      expect(bucket.durationMs, 90000);
      expect(bucket.pagesTurned, 5);
      expect(bucket.charactersRead, 1000);
      expect(bucket.lookups, 5);
    });

    test('clamps negative counters to zero instead of dropping the row', () {
      final buckets = bucketize(
        [
          _session(
            id: 1,
            startedAt: DateTime(2026, 2, 12, 8),
            durationMs: -600000,
            charactersRead: -50,
            pagesTurned: -2,
            lookups: -1,
          ),
          _session(
            id: 2,
            startedAt: DateTime(2026, 2, 12, 9),
            durationMs: 60000,
            charactersRead: 500,
            pagesTurned: 2,
            lookups: 3,
          ),
        ],
        StatsPeriod.week,
        now,
      );

      final bucket = buckets[3];
      expect(bucket.durationMs, 60000);
      expect(bucket.charactersRead, 500);
      expect(bucket.pagesTurned, 2);
      expect(bucket.lookups, 3);
    });

    test('ignores the book format (callers filter first)', () {
      final buckets = bucketize(
        [
          _session(
            id: 1,
            bookFormat: 'manga',
            startedAt: DateTime(2026, 2, 15, 9),
            durationMs: 1000,
          ),
        ],
        StatsPeriod.week,
        now,
      );

      expect(buckets.last.durationMs, 1000);
    });
  });

  group('bucketize month', () {
    test('returns 30 day buckets ending today', () {
      final buckets = bucketize(const [], StatsPeriod.month, now);

      expect(buckets, hasLength(30));
      expect(buckets.first.start, DateTime(2026, 1, 17));
      expect(buckets.last.start, DateTime(2026, 2, 15));
    });

    test('day 30 is inside the window and day 31 is outside', () {
      final buckets = bucketize(
        [
          _session(
            id: 1,
            startedAt: DateTime(2026, 1, 17, 6),
            durationMs: 4000,
          ),
          _session(
            id: 2,
            startedAt: DateTime(2026, 1, 16, 23, 59),
            durationMs: 8000,
          ),
        ],
        StatsPeriod.month,
        now,
      );

      expect(buckets.first.durationMs, 4000);
      expect(buckets.fold<int>(0, (sum, b) => sum + b.durationMs), 4000);
    });
  });

  group('bucketize year', () {
    test('returns 12 month buckets ending with the current month', () {
      final buckets = bucketize(const [], StatsPeriod.year, now);

      expect(buckets, hasLength(12));
      expect(buckets.first.start, DateTime(2025, 3, 1));
      expect(buckets.last.start, DateTime(2026, 2, 1));
    });

    test('buckets months across a year boundary', () {
      final buckets = bucketize(
        [
          _session(
            id: 1,
            startedAt: DateTime(2025, 12, 31, 23, 59),
            durationMs: 7000,
            charactersRead: 700,
          ),
          _session(
            id: 2,
            startedAt: DateTime(2026, 1, 1, 0, 1),
            durationMs: 3000,
            charactersRead: 300,
          ),
        ],
        StatsPeriod.year,
        now,
      );

      expect(buckets[9].start, DateTime(2025, 12, 1));
      expect(buckets[9].durationMs, 7000);
      expect(buckets[9].charactersRead, 700);
      expect(buckets[10].start, DateTime(2026, 1, 1));
      expect(buckets[10].durationMs, 3000);
      expect(buckets[10].charactersRead, 300);
    });

    test('aggregates every day of a month into one bucket', () {
      final buckets = bucketize(
        [
          _session(id: 1, startedAt: DateTime(2025, 6, 1), durationMs: 1000),
          _session(id: 2, startedAt: DateTime(2025, 6, 15), durationMs: 2000),
          _session(
            id: 3,
            startedAt: DateTime(2025, 6, 30, 23),
            durationMs: 3000,
          ),
        ],
        StatsPeriod.year,
        now,
      );

      expect(buckets[3].start, DateTime(2025, 6, 1));
      expect(buckets[3].durationMs, 6000);
    });

    test('drops months older than the 12-month window', () {
      final buckets = bucketize(
        [
          _session(
            id: 1,
            startedAt: DateTime(2025, 2, 28, 23, 59),
            durationMs: 9000,
          ),
        ],
        StatsPeriod.year,
        now,
      );

      expect(buckets.fold<int>(0, (sum, b) => sum + b.durationMs), 0);
    });

    test('empty months are present with zeros', () {
      final buckets = bucketize(
        [_session(id: 1, startedAt: DateTime(2026, 2, 2), durationMs: 5000)],
        StatsPeriod.year,
        now,
      );

      expect(buckets, hasLength(12));
      expect(buckets.take(11).every((b) => b.durationMs == 0), isTrue);
      expect(buckets.last.durationMs, 5000);
    });
  });

  group('bucketize all', () {
    test('spans month buckets from the first session to the current month', () {
      final buckets = bucketize(
        [
          _session(id: 1, startedAt: DateTime(2026, 1, 20), durationMs: 1000),
          _session(id: 2, startedAt: DateTime(2026, 4, 2), durationMs: 4000),
        ],
        StatsPeriod.all,
        DateTime(2026, 4, 10, 8),
      );

      expect(buckets.map((b) => b.start), [
        DateTime(2026, 1, 1),
        DateTime(2026, 2, 1),
        DateTime(2026, 3, 1),
        DateTime(2026, 4, 1),
      ]);
      expect(buckets.map((b) => b.durationMs), [1000, 0, 0, 4000]);
    });

    test('spans a year boundary', () {
      final buckets = bucketize(
        [_session(id: 1, startedAt: DateTime(2025, 11, 30), durationMs: 1000)],
        StatsPeriod.all,
        now,
      );

      expect(buckets.map((b) => b.start), [
        DateTime(2025, 11, 1),
        DateTime(2025, 12, 1),
        DateTime(2026, 1, 1),
        DateTime(2026, 2, 1),
      ]);
    });

    test('falls back to a single zeroed current-month bucket with no data', () {
      final buckets = bucketize(const [], StatsPeriod.all, now);

      expect(buckets, hasLength(1));
      expect(buckets.single.start, DateTime(2026, 2, 1));
      expect(buckets.single.durationMs, 0);
    });

    test('ignores sessions in future months when picking the first month', () {
      final buckets = bucketize(
        [_session(id: 1, startedAt: DateTime(2026, 6, 1), durationMs: 9000)],
        StatsPeriod.all,
        now,
      );

      expect(buckets, hasLength(1));
      expect(buckets.single.start, DateTime(2026, 2, 1));
      expect(buckets.single.durationMs, 0);
    });

    test('is not confused by unsorted input', () {
      final buckets = bucketize(
        [
          _session(id: 1, startedAt: DateTime(2026, 2, 3), durationMs: 1000),
          _session(id: 2, startedAt: DateTime(2025, 12, 3), durationMs: 2000),
        ],
        StatsPeriod.all,
        now,
      );

      expect(buckets.first.start, DateTime(2025, 12, 1));
      expect(buckets, hasLength(3));
    });
  });

  group('heatmapDays', () {
    test('returns exactly 365 entries ending today', () {
      final days = heatmapDays(const [], now);

      expect(days, hasLength(365));
      expect(days.last.day, DateTime(2026, 2, 15));
      expect(days.first.day, DateTime(2025, 2, 16));
    });

    test('empty days are present with zeros', () {
      final days = heatmapDays(const [], now);

      expect(days.every((d) => d.minutes == 0), isTrue);
      expect(days.every((d) => d.charactersRead == 0), isTrue);
      expect(days.every((d) => d.lookups == 0), isTrue);
    });

    test('floors summed milliseconds to whole minutes', () {
      final days = heatmapDays([
        // 90_000 + 60_000 = 150_000 ms = 2.5 minutes -> 2, not 3.
        _session(id: 1, startedAt: DateTime(2026, 2, 14, 9), durationMs: 90000),
        _session(
          id: 2,
          startedAt: DateTime(2026, 2, 14, 20),
          durationMs: 60000,
        ),
        // 45_000 ms = 0.75 minutes -> 0, not 1.
        _session(id: 3, startedAt: DateTime(2026, 2, 13, 9), durationMs: 45000),
      ], now);

      expect(days[363].day, DateTime(2026, 2, 14));
      expect(days[363].minutes, 2);
      expect(days[362].day, DateTime(2026, 2, 13));
      expect(days[362].minutes, 0);
    });

    test('a sub-minute day still reports its characters and lookups', () {
      // Guards the documented contract that a day is "active" when any of
      // minutes/characters/lookups is non-zero, not minutes alone.
      final days = heatmapDays([
        _session(
          id: 1,
          startedAt: DateTime(2026, 2, 15, 9),
          durationMs: 20000,
          charactersRead: 120,
          lookups: 2,
        ),
      ], now);

      expect(days.last.minutes, 0);
      expect(days.last.charactersRead, 120);
      expect(days.last.lookups, 2);
    });

    test('sums characters and lookups per day', () {
      final days = heatmapDays([
        _session(
          id: 1,
          startedAt: DateTime(2026, 2, 15, 9),
          charactersRead: 400,
          lookups: 2,
        ),
        _session(
          id: 2,
          startedAt: DateTime(2026, 2, 15, 10),
          charactersRead: 600,
          lookups: 3,
        ),
      ], now);

      expect(days.last.charactersRead, 1000);
      expect(days.last.lookups, 5);
    });

    test('clamps negative durations to zero', () {
      final days = heatmapDays([
        _session(
          id: 1,
          startedAt: DateTime(2026, 2, 15, 9),
          durationMs: -600000,
        ),
        _session(
          id: 2,
          startedAt: DateTime(2026, 2, 15, 10),
          durationMs: 120000,
        ),
      ], now);

      expect(days.last.minutes, 2);
    });

    test('excludes days outside the trailing 365-day window', () {
      final days = heatmapDays([
        _session(
          id: 1,
          startedAt: DateTime(2025, 2, 16, 12),
          durationMs: 600000,
        ),
        _session(
          id: 2,
          startedAt: DateTime(2025, 2, 15, 12),
          durationMs: 600000,
        ),
        _session(id: 3, startedAt: DateTime(2026, 2, 16), durationMs: 600000),
      ], now);

      expect(days.first.minutes, 10);
      expect(days.fold<int>(0, (sum, d) => sum + d.minutes), 10);
    });
  });

  group('lookupRatePer1k', () {
    test('is null when no characters were read', () {
      final bucket = StatBucket(
        start: DateTime(2026, 2, 15),
        durationMs: 0,
        charactersRead: 0,
        pagesTurned: 0,
        lookups: 7,
      );

      expect(lookupRatePer1k(bucket), isNull);
    });

    test('scales lookups to a per-1000-character rate', () {
      final bucket = StatBucket(
        start: DateTime(2026, 2, 15),
        durationMs: 0,
        charactersRead: 5000,
        pagesTurned: 0,
        lookups: 10,
      );

      expect(lookupRatePer1k(bucket), 2.0);
    });

    test('is zero when characters were read without lookups', () {
      final bucket = StatBucket(
        start: DateTime(2026, 2, 15),
        durationMs: 0,
        charactersRead: 1200,
        pagesTurned: 0,
        lookups: 0,
      );

      expect(lookupRatePer1k(bucket), 0.0);
    });
  });

  group('cumulativeUniqueWords', () {
    test('returns no points for no events', () {
      expect(cumulativeUniqueWords(const []), isEmpty);
    });

    test('counts each expression once, at its first event', () {
      final points = cumulativeUniqueWords([
        _event(
          id: 1,
          kind: 'saved',
          expression: '猫',
          createdAt: DateTime(2026, 2, 10, 9),
        ),
        _event(
          id: 2,
          kind: 'anki',
          expression: '猫',
          createdAt: DateTime(2026, 2, 12, 9),
        ),
      ]);

      expect(points, hasLength(1));
      expect(points.single.day, DateTime(2026, 2, 10));
      expect(points.single.total, 1);
    });

    test('dedupes across mixed saved and anki kinds while accumulating', () {
      final points = cumulativeUniqueWords([
        _event(
          id: 1,
          kind: 'saved',
          expression: '猫',
          createdAt: DateTime(2026, 2, 10, 9),
        ),
        _event(
          id: 2,
          kind: 'anki',
          expression: '猫',
          createdAt: DateTime(2026, 2, 10, 10),
        ),
        _event(
          id: 3,
          kind: 'anki',
          expression: '犬',
          createdAt: DateTime(2026, 2, 11, 9),
        ),
        _event(
          id: 4,
          kind: 'saved',
          expression: '鳥',
          createdAt: DateTime(2026, 2, 11, 23, 59),
        ),
      ]);

      expect(points.map((p) => p.day), [
        DateTime(2026, 2, 10),
        DateTime(2026, 2, 11),
      ]);
      expect(points.map((p) => p.total), [1, 3]);
    });

    test('emits one point per day, holding the end-of-day running total', () {
      final points = cumulativeUniqueWords([
        _event(id: 1, expression: 'a', createdAt: DateTime(2026, 1, 1, 8)),
        _event(id: 2, expression: 'b', createdAt: DateTime(2026, 1, 1, 20)),
        _event(id: 3, expression: 'c', createdAt: DateTime(2026, 1, 5, 8)),
      ]);

      expect(points, hasLength(2));
      expect(points.first.day, DateTime(2026, 1, 1));
      expect(points.first.total, 2);
      expect(points.last.day, DateTime(2026, 1, 5));
      expect(points.last.total, 3);
    });

    test('omits days that only repeat known expressions', () {
      final points = cumulativeUniqueWords([
        _event(id: 1, expression: 'a', createdAt: DateTime(2026, 1, 1, 8)),
        _event(id: 2, expression: 'a', createdAt: DateTime(2026, 1, 2, 8)),
        _event(id: 3, expression: 'b', createdAt: DateTime(2026, 1, 3, 8)),
      ]);

      expect(points.map((p) => p.day), [
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 3),
      ]);
      expect(points.map((p) => p.total), [1, 2]);
    });

    test('sorts unordered events before deduping', () {
      final points = cumulativeUniqueWords([
        _event(id: 2, expression: '猫', createdAt: DateTime(2026, 2, 12, 9)),
        _event(id: 1, expression: '猫', createdAt: DateTime(2026, 2, 10, 9)),
      ]);

      expect(points, hasLength(1));
      expect(points.single.day, DateTime(2026, 2, 10));
    });

    test('does not mutate the input list', () {
      final events = [
        _event(id: 2, expression: 'b', createdAt: DateTime(2026, 2, 12)),
        _event(id: 1, expression: 'a', createdAt: DateTime(2026, 2, 10)),
      ];
      final snapshot = [...events];

      cumulativeUniqueWords(events);

      expect(events, snapshot);
    });
  });

  group('bestDay', () {
    test('is null when there are no sessions', () {
      expect(bestDay(const [], now), isNull);
    });

    test('picks the day with the highest total duration', () {
      final best = bestDay([
        _session(
          id: 1,
          startedAt: DateTime(2026, 2, 10, 9),
          durationMs: 600000,
          charactersRead: 100,
        ),
        _session(
          id: 2,
          startedAt: DateTime(2026, 2, 10, 21),
          durationMs: 300000,
          charactersRead: 200,
        ),
        _session(
          id: 3,
          startedAt: DateTime(2026, 2, 12, 9),
          durationMs: 1000000,
          charactersRead: 50,
        ),
      ], now);

      expect(best!.start, DateTime(2026, 2, 12));
      expect(best.durationMs, 1000000);
      expect(best.charactersRead, 50);
    });

    test('aggregates the whole winning day', () {
      final best = bestDay([
        _session(
          id: 1,
          startedAt: DateTime(2026, 2, 10, 9),
          durationMs: 600000,
          charactersRead: 100,
          pagesTurned: 3,
          lookups: 2,
        ),
        _session(
          id: 2,
          startedAt: DateTime(2026, 2, 10, 21),
          durationMs: 300000,
          charactersRead: 200,
          pagesTurned: 4,
          lookups: 5,
        ),
        _session(id: 3, startedAt: DateTime(2026, 2, 12, 9), durationMs: 10000),
      ], now);

      expect(best!.start, DateTime(2026, 2, 10));
      expect(best.durationMs, 900000);
      expect(best.charactersRead, 300);
      expect(best.pagesTurned, 7);
      expect(best.lookups, 7);
    });

    test('looks past the trailing windows, all the way back', () {
      final best = bestDay([
        _session(
          id: 1,
          startedAt: DateTime(2021, 5, 4, 9),
          durationMs: 9000000,
        ),
        _session(id: 2, startedAt: DateTime(2026, 2, 12, 9), durationMs: 10000),
      ], now);

      expect(best!.start, DateTime(2021, 5, 4));
      expect(best.durationMs, 9000000);
    });

    test('breaks ties in favour of the earliest day', () {
      final best = bestDay([
        _session(
          id: 1,
          startedAt: DateTime(2026, 2, 12, 9),
          durationMs: 600000,
        ),
        _session(
          id: 2,
          startedAt: DateTime(2026, 2, 10, 9),
          durationMs: 600000,
        ),
      ], now);

      expect(best!.start, DateTime(2026, 2, 10));
    });

    test('ignores sessions dated after today', () {
      final best = bestDay([
        _session(
          id: 1,
          startedAt: DateTime(2026, 2, 16, 9),
          durationMs: 9000000,
        ),
        _session(id: 2, startedAt: DateTime(2026, 2, 12, 9), durationMs: 10000),
      ], now);

      expect(best!.start, DateTime(2026, 2, 12));
      expect(best.durationMs, 10000);
    });

    test('is null when every session is dated after today', () {
      final best = bestDay([
        _session(id: 1, startedAt: DateTime(2026, 2, 16, 9), durationMs: 10000),
      ], now);

      expect(best, isNull);
    });

    test('clamps negative durations to zero', () {
      final best = bestDay([
        _session(
          id: 1,
          startedAt: DateTime(2026, 2, 10, 9),
          durationMs: -900000,
        ),
        _session(id: 2, startedAt: DateTime(2026, 2, 12, 9), durationMs: 1000),
      ], now);

      expect(best!.start, DateTime(2026, 2, 12));
      expect(best.durationMs, 1000);
    });
  });
}
