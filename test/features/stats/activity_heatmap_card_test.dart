import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/stats/data/services/stats_aggregator.dart';
import 'package:mekuru/features/stats/presentation/widgets/activity_heatmap_card.dart';

import '../../test_app.dart';

/// The grid's cell pitch, mirrored here so a tap can be aimed at one cell.
const double _cellPitch = 14;
const double _halfCell = 5.5;

HeatmapDay _day(
  DateTime day, {
  int minutes = 0,
  int charactersRead = 0,
  int lookups = 0,
}) => HeatmapDay(
  day: day,
  minutes: minutes,
  charactersRead: charactersRead,
  lookups: lookups,
);

/// 365 days ending on [today], with the days listed in [active] filled in.
///
/// Keys of [active] count backwards from today, so `0` is today itself.
List<HeatmapDay> _syntheticYear(
  DateTime today, {
  Map<int, ({int minutes, int charactersRead, int lookups})> active = const {},
}) {
  final days = <HeatmapDay>[];
  for (var offset = 364; offset >= 0; offset--) {
    final values = active[offset];
    days.add(
      _day(
        DateTime(today.year, today.month, today.day - offset),
        minutes: values?.minutes ?? 0,
        charactersRead: values?.charactersRead ?? 0,
        lookups: values?.lookups ?? 0,
      ),
    );
  }
  return days;
}

/// Where today's cell sits: last column, and the row its weekday falls on
/// under an en_US week (which starts on Sunday).
Offset _todaysCell(Rect grid, DateTime today) => Offset(
  grid.right - _halfCell,
  grid.top + today.weekday % 7 * _cellPitch + _halfCell,
);

void main() {
  group('heatmapIntensityStep', () {
    test('leaves a day with nothing recorded off the ramp', () {
      expect(heatmapIntensityStep(_day(DateTime(2026, 8, 1))), isNull);
    });

    test('counts a sub-minute day as active at the lowest step', () {
      // The aggregator floors minutes, so a short session reads as zero — but
      // it is still a day the reader showed up, and must not render empty.
      expect(
        heatmapIntensityStep(_day(DateTime(2026, 8, 1), charactersRead: 40)),
        0,
      );
      expect(heatmapIntensityStep(_day(DateTime(2026, 8, 1), lookups: 1)), 0);
    });

    test('steps up at each minute threshold', () {
      DateTime day() => DateTime(2026, 8, 1);
      expect(heatmapIntensityStep(_day(day(), minutes: 1)), 0);
      expect(heatmapIntensityStep(_day(day(), minutes: 14)), 0);
      expect(heatmapIntensityStep(_day(day(), minutes: 15)), 1);
      expect(heatmapIntensityStep(_day(day(), minutes: 29)), 1);
      expect(heatmapIntensityStep(_day(day(), minutes: 30)), 2);
      expect(heatmapIntensityStep(_day(day(), minutes: 59)), 2);
      expect(heatmapIntensityStep(_day(day(), minutes: 60)), 3);
      expect(heatmapIntensityStep(_day(day(), minutes: 600)), 3);
    });
  });

  group('ActivityHeatmapCard', () {
    Future<void> pumpCard(
      WidgetTester tester, {
      required List<HeatmapDay> days,
      ValueChanged<HeatmapDay>? onDayTap,
    }) async {
      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: Scaffold(
            body: ActivityHeatmapCard(days: days, onDayTap: onDayTap ?? (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('renders a year of cells with its title and scale', (
      tester,
    ) async {
      await pumpCard(tester, days: _syntheticYear(DateTime(2026, 8, 1)));

      expect(find.text('Reading activity'), findsOneWidget);
      expect(find.text('Less'), findsOneWidget);
      expect(find.text('More'), findsOneWidget);
      expect(find.byKey(ActivityHeatmapCard.gridKey), findsOneWidget);
      // A full year always spans every month, whatever today happens to be.
      expect(find.text('Jan'), findsOneWidget);
      expect(find.text('Dec'), findsOneWidget);
    });

    testWidgets('renders nothing when there are no days to show', (
      tester,
    ) async {
      await pumpCard(tester, days: const []);

      expect(find.byKey(ActivityHeatmapCard.gridKey), findsNothing);
      expect(find.text('Reading activity'), findsNothing);
    });

    testWidgets('reports the day behind the tapped cell', (tester) async {
      final today = DateTime(2026, 8, 1);
      HeatmapDay? tapped;
      await pumpCard(
        tester,
        days: _syntheticYear(
          today,
          active: {0: (minutes: 95, charactersRead: 4200, lookups: 12)},
        ),
        onDayTap: (day) => tapped = day,
      );

      // The grid opens scrolled to its recent end, so today's column is the
      // rightmost one on screen.
      final grid = tester.getRect(find.byKey(ActivityHeatmapCard.gridKey));
      await tester.tapAt(_todaysCell(grid, today));
      await tester.pump();

      expect(tapped?.day, today);
      expect(tapped?.minutes, 95);
      expect(tapped?.charactersRead, 4200);
      expect(tapped?.lookups, 12);
    });

    testWidgets('ignores a tap that lands past the last day', (tester) async {
      final today = DateTime(2026, 8, 1);
      var taps = 0;
      await pumpCard(
        tester,
        days: _syntheticYear(today),
        onDayTap: (_) => taps++,
      );

      // The year starts partway down column zero — 2025-08-02 is a Saturday —
      // so the top-left cell precedes every day in the list and belongs to no
      // day at all.
      final grid = tester.getRect(find.byKey(ActivityHeatmapCard.gridKey));
      await tester.tapAt(Offset(grid.left + _halfCell, grid.top + _halfCell));
      await tester.pump();

      expect(taps, 0);
    });

    testWidgets('skips the entrance fade when animations are disabled', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: Scaffold(
                body: ActivityHeatmapCard(
                  days: _syntheticYear(DateTime(2026, 8, 1)),
                  onDayTap: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      // One frame, no settling: with animations off the card is already whole.
      await tester.pump();

      final opacity = tester.widget<Opacity>(
        find
            .descendant(
              of: find.byType(ActivityHeatmapCard),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(opacity.opacity, 1);
    });
  });
}
