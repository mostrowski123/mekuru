import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/stats/data/services/stats_aggregator.dart';
import 'package:mekuru/features/stats/presentation/widgets/lookup_rate_card.dart';
import 'package:mekuru/features/stats/presentation/widgets/reading_time_card.dart';
import 'package:mekuru/features/stats/presentation/widgets/stats_chart_card.dart';
import 'package:mekuru/features/stats/presentation/widgets/vocab_growth_card.dart';
import 'package:mekuru/features/stats/presentation/widgets/volume_card.dart';

import '../../test_app.dart';

const int _minute = Duration.millisecondsPerMinute;

StatBucket _bucket(
  DateTime start, {
  int minutes = 0,
  int charactersRead = 0,
  int pagesTurned = 0,
  int lookups = 0,
}) => StatBucket(
  start: start,
  durationMs: minutes * _minute,
  charactersRead: charactersRead,
  pagesTurned: pagesTurned,
  lookups: lookups,
);

/// Three consecutive days ending on 2026-08-01.
List<DateTime> _days() => [
  DateTime(2026, 7, 30),
  DateTime(2026, 7, 31),
  DateTime(2026, 8, 1),
];

Future<void> _pump(WidgetTester tester, Widget card) async {
  await tester.pumpWidget(buildLocalizedTestApp(home: Scaffold(body: card)));
  await tester.pumpAndSettle();
}

void main() {
  group('ReadingTimeCard', () {
    List<StatBucket> epub() => [
      _bucket(_days()[0], minutes: 20),
      _bucket(_days()[1], minutes: 45),
      _bucket(_days()[2], minutes: 10),
    ];

    List<StatBucket> manga() => [
      _bucket(_days()[0], minutes: 5),
      _bucket(_days()[1]),
      _bucket(_days()[2], minutes: 30),
    ];

    testWidgets('renders its title and bars for both formats', (tester) async {
      await _pump(
        tester,
        ReadingTimeCard(
          epubBuckets: epub(),
          mangaBuckets: manga(),
          period: StatsPeriod.week,
        ),
      );

      expect(find.text('Reading time'), findsOneWidget);
      final chart = tester.widget<BarChart>(find.byType(BarChart));
      expect(chart.data.barGroups, hasLength(3));
      // The dark theme paints cards in the tooltip's own color, so the
      // tooltip needs an edge to read as a popover rather than as nothing.
      expect(
        chart.data.barTouchData.touchTooltipData.tooltipBorder,
        isNot(BorderSide.none),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('stacks the two formats into one rod each', (tester) async {
      await _pump(
        tester,
        ReadingTimeCard(
          epubBuckets: epub(),
          mangaBuckets: manga(),
          period: StatsPeriod.week,
        ),
      );

      final chart = tester.widget<BarChart>(find.byType(BarChart));
      final rod = chart.data.barGroups.first.barRods.single;
      expect(rod.rodStackItems, hasLength(2));
      // 20 EPUB minutes under 5 manga minutes, stacked to 25.
      expect(rod.rodStackItems.first.toY, 20);
      expect(rod.toY, 25);
    });

    testWidgets('shows the legend only when both formats are present', (
      tester,
    ) async {
      await _pump(
        tester,
        ReadingTimeCard(
          epubBuckets: epub(),
          mangaBuckets: manga(),
          period: StatsPeriod.week,
        ),
      );

      expect(find.text('EPUB'), findsOneWidget);
      expect(find.text('Manga'), findsOneWidget);

      await _pump(
        tester,
        ReadingTimeCard(
          epubBuckets: epub(),
          mangaBuckets: const [],
          period: StatsPeriod.week,
        ),
      );

      expect(find.text('EPUB'), findsNothing);
      expect(find.text('Manga'), findsNothing);
      final chart = tester.widget<BarChart>(find.byType(BarChart));
      expect(chart.data.barGroups.first.barRods.single.rodStackItems, isEmpty);
    });

    testWidgets('keeps manga on its own color when it is the only series', (
      tester,
    ) async {
      // The format hues are pinned to the format: dropping EPUB out of the
      // chart must not promote manga onto the EPUB color.
      await _pump(
        tester,
        ReadingTimeCard(
          epubBuckets: const [],
          mangaBuckets: manga(),
          period: StatsPeriod.week,
        ),
      );

      final colors = Theme.of(
        tester.element(find.byType(BarChart)),
      ).colorScheme;
      expect(mangaSeriesColor(colors), isNot(epubSeriesColor(colors)));

      final chart = tester.widget<BarChart>(find.byType(BarChart));
      expect(
        chart.data.barGroups.map((g) => g.barRods.single.color),
        everyElement(mangaSeriesColor(colors)),
      );
    });

    testWidgets('annotates the best day when it falls inside the window', (
      tester,
    ) async {
      await _pump(
        tester,
        ReadingTimeCard(
          epubBuckets: epub(),
          mangaBuckets: const [],
          period: StatsPeriod.week,
          bestDay: _bucket(_days()[1], minutes: 45),
        ),
      );

      final chart = tester.widget<BarChart>(find.byType(BarChart));
      final labels = [
        for (final group in chart.data.barGroups)
          group.barRods.single.label.show,
      ];
      expect(labels, [false, true, false]);
    });

    testWidgets('leaves month buckets unannotated', (tester) async {
      // A month-wide bar is not a day, so calling one "best day" would be a
      // claim the chart is not making.
      await _pump(
        tester,
        ReadingTimeCard(
          epubBuckets: [
            _bucket(DateTime(2026, 7), minutes: 300),
            _bucket(DateTime(2026, 8), minutes: 120),
          ],
          mangaBuckets: const [],
          period: StatsPeriod.year,
          bestDay: _bucket(DateTime(2026, 7), minutes: 45),
        ),
      );

      final chart = tester.widget<BarChart>(find.byType(BarChart));
      expect(
        chart.data.barGroups.every((g) => !g.barRods.single.label.show),
        isTrue,
      );
    });

    testWidgets('renders nothing without buckets', (tester) async {
      await _pump(
        tester,
        const ReadingTimeCard(
          epubBuckets: [],
          mangaBuckets: [],
          period: StatsPeriod.week,
        ),
      );

      expect(find.byType(BarChart), findsNothing);
      expect(find.text('Reading time'), findsNothing);
    });
  });

  group('VolumeCard', () {
    testWidgets('renders its title, bars and the page figure', (tester) async {
      await _pump(
        tester,
        VolumeCard(
          buckets: [
            _bucket(_days()[0], charactersRead: 4200, pagesTurned: 8),
            _bucket(_days()[1], charactersRead: 1500, pagesTurned: 3),
            _bucket(_days()[2], charactersRead: 0),
          ],
          period: StatsPeriod.week,
        ),
      );

      expect(find.text('Characters read'), findsOneWidget);
      // Pages are a figure in the header, never a second axis.
      expect(find.text('11 pages'), findsOneWidget);
      final chart = tester.widget<BarChart>(find.byType(BarChart));
      expect(chart.data.barGroups, hasLength(3));
      expect(chart.data.barGroups.first.barRods.single.toY, 4200);
      expect(tester.takeException(), isNull);
    });

    testWidgets('drops the page figure when nothing was paged', (tester) async {
      await _pump(
        tester,
        VolumeCard(
          buckets: [_bucket(_days()[0], charactersRead: 900)],
          period: StatsPeriod.week,
        ),
      );

      expect(find.textContaining('page'), findsNothing);
    });
  });

  // The build-zero-then-fill entrance is owned by StatsChartCard on behalf of
  // all four cards; VolumeCard is just the cheapest one to drive it through.
  group('StatsChartCard entrance', () {
    Widget card() => VolumeCard(
      buckets: [_bucket(_days()[0], charactersRead: 4200)],
      period: StatsPeriod.week,
    );

    double toY(WidgetTester tester) => tester
        .widget<BarChart>(find.byType(BarChart))
        .data
        .barGroups
        .single
        .barRods
        .single
        .toY;

    testWidgets('opens at the baseline and grows into the real values', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildLocalizedTestApp(home: Scaffold(body: card())),
      );

      // First frame: nothing for fl_chart to animate away from yet.
      expect(toY(tester), 0);

      await tester.pumpAndSettle();
      expect(toY(tester), 4200);
    });

    testWidgets('is already whole when animations are disabled', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: Scaffold(body: card()),
            ),
          ),
        ),
      );

      expect(toY(tester), 4200);
      expect(
        tester.widget<BarChart>(find.byType(BarChart)).duration,
        Duration.zero,
      );
    });
  });

  group('LookupRateCard', () {
    testWidgets('renders its title, subtitle and trend line', (tester) async {
      await _pump(
        tester,
        LookupRateCard(
          buckets: [
            _bucket(_days()[0], charactersRead: 1000, lookups: 12),
            _bucket(_days()[1], charactersRead: 2000, lookups: 10),
            _bucket(_days()[2], charactersRead: 500, lookups: 1),
          ],
          period: StatsPeriod.week,
        ),
      );

      expect(find.text('Lookup rate'), findsOneWidget);
      expect(find.text('Lookups per 1,000 characters'), findsOneWidget);
      final chart = tester.widget<LineChart>(find.byType(LineChart));
      expect(chart.data.lineBarsData, hasLength(1));
      expect(chart.data.lineBarsData.single.spots.first.y, 12);
      expect(
        chart.data.lineTouchData.touchTooltipData.tooltipBorder,
        isNot(BorderSide.none),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('reserves axis width from its labels, not a fixed gutter', (
      tester,
    ) async {
      // The reservation is measured from the tick strings themselves — the
      // old fixed 44px gutter left short labels like "10" floating in a band
      // of dead space between the card's edge and the plot. Assert the
      // behavior (narrow labels reserve less than wide ones) rather than a
      // pixel count, because the test font renders every glyph an em wide.
      Future<double> reservedFor(List<StatBucket> buckets) async {
        await _pump(
          tester,
          LookupRateCard(buckets: buckets, period: StatsPeriod.week),
        );
        final chart = tester.widget<LineChart>(find.byType(LineChart));
        return chart.data.titlesData.leftTitles.sideTitles.reservedSize;
      }

      final narrow = await reservedFor([
        _bucket(_days()[0], charactersRead: 1000, lookups: 12),
        _bucket(_days()[1], charactersRead: 2000, lookups: 10),
      ]);
      final wide = await reservedFor([
        _bucket(_days()[0], charactersRead: 1000, lookups: 900),
        _bucket(_days()[1], charactersRead: 2000, lookups: 10),
      ]);

      expect(narrow, greaterThan(10));
      expect(narrow, lessThan(wide));
    });

    testWidgets('breaks the line where a bucket has no characters', (
      tester,
    ) async {
      await _pump(
        tester,
        LookupRateCard(
          buckets: [
            _bucket(_days()[0], charactersRead: 1000, lookups: 12),
            // Nothing to divide by: a gap, not a rate of zero.
            _bucket(_days()[1], lookups: 4),
            _bucket(_days()[2], charactersRead: 500, lookups: 1),
          ],
          period: StatsPeriod.week,
        ),
      );

      final chart = tester.widget<LineChart>(find.byType(LineChart));
      expect(chart.data.lineBarsData, hasLength(2));
      expect(chart.data.lineBarsData[0].spots.single.x, 0);
      expect(chart.data.lineBarsData[1].spots.single.x, 2);
    });

    testWidgets('renders nothing when no bucket has a rate', (tester) async {
      await _pump(
        tester,
        LookupRateCard(
          buckets: [_bucket(_days()[0], lookups: 3)],
          period: StatsPeriod.week,
        ),
      );

      expect(find.byType(LineChart), findsNothing);
      expect(find.text('Lookup rate'), findsNothing);
    });
  });

  group('vocabGrowthDomain', () {
    test('carries the last total forward to the end of the window', () {
      final domain = vocabGrowthDomain(
        [
          CumulativePoint(day: DateTime(2026, 7, 26), total: 4),
          CumulativePoint(day: DateTime(2026, 7, 28), total: 9),
        ],
        DateTime(2026, 7, 26),
        DateTime(2026, 8, 1, 13, 30),
      );

      // Six days after the window opened, still at the nine words reached on
      // day two — the curve spans the window instead of dying at the last
      // new word.
      expect(domain.spots.last, const FlSpot(6, 9));
      expect(domain.spots, hasLength(3));
    });

    test('carries words learned before the window into its first value', () {
      final domain = vocabGrowthDomain(
        [
          CumulativePoint(day: DateTime(2026, 6, 1), total: 40),
          CumulativePoint(day: DateTime(2026, 7, 28), total: 42),
        ],
        DateTime(2026, 7, 26),
        DateTime(2026, 8, 1),
      );

      expect(domain.start, DateTime(2026, 7, 26));
      expect(domain.spots.first, const FlSpot(0, 40));
      expect(domain.spots[1], const FlSpot(2, 42));
      expect(domain.spots.last, const FlSpot(6, 42));
    });

    test('runs flat across a window that added nothing', () {
      final domain = vocabGrowthDomain(
        [CumulativePoint(day: DateTime(2026, 6, 1), total: 40)],
        DateTime(2026, 7, 26),
        DateTime(2026, 8, 1),
      );

      expect(domain.spots, const [FlSpot(0, 40), FlSpot(6, 40)]);
    });

    test('opens at the first word when the window has no lower bound', () {
      final domain = vocabGrowthDomain(
        [
          CumulativePoint(day: DateTime(2026, 7, 26), total: 1),
          CumulativePoint(day: DateTime(2026, 7, 30), total: 5),
        ],
        null,
        DateTime(2026, 8, 1),
      );

      expect(domain.start, DateTime(2026, 7, 26));
      expect(domain.spots.first, const FlSpot(0, 1));
      expect(domain.spots.last, const FlSpot(6, 5));
    });
  });

  group('VocabGrowthCard', () {
    testWidgets('renders its title, curve and end label', (tester) async {
      await _pump(
        tester,
        VocabGrowthCard(
          points: [
            CumulativePoint(day: DateTime(2026, 7, 26), total: 4),
            CumulativePoint(day: DateTime(2026, 7, 28), total: 9),
          ],
          windowStart: DateTime(2026, 7, 26),
          windowEnd: DateTime(2026, 8, 1),
        ),
      );

      expect(find.text('Vocabulary growth'), findsOneWidget);
      final chart = tester.widget<LineChart>(find.byType(LineChart));
      final spots = chart.data.lineBarsData.single.spots;
      // The synthetic terminal point the sparse series does not carry itself.
      expect(spots.last, const FlSpot(6, 9));
      // The final value, direct-labelled at the line's end.
      expect(find.text('9'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders nothing before the first word is saved', (
      tester,
    ) async {
      await _pump(
        tester,
        VocabGrowthCard(
          points: const [],
          windowStart: DateTime(2026, 7, 26),
          windowEnd: DateTime(2026, 8, 1),
        ),
      );

      expect(find.byType(LineChart), findsNothing);
      expect(find.text('Vocabulary growth'), findsNothing);
    });
  });
}
