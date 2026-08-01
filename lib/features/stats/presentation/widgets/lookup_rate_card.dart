import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mekuru/features/stats/data/services/stats_aggregator.dart';
import 'package:mekuru/features/stats/presentation/widgets/stats_chart_card.dart';
import 'package:mekuru/l10n/l10n.dart';

/// Stroke width of the trend line.
const double _lineWidth = 2;

/// Radius of the dot under a finger. Ten logical pixels across, so the mark
/// the tooltip refers to is never smaller than the thing that summoned it.
const double _touchDotRadius = 5;

/// Radius of a bucket that has no neighbour to draw a line to.
const double _loneSpotRadius = 3;

/// Lookups per 1,000 characters per bucket, as a trend line.
///
/// A bucket with no characters counted has no rate — not a rate of zero — so
/// it leaves a gap in the line rather than a dip to the axis. fl_chart draws
/// one continuous line per [LineChartBarData], so each unbroken run of buckets
/// becomes its own line and the gaps fall out between them.
class LookupRateCard extends StatelessWidget {
  const LookupRateCard({
    super.key,
    required this.buckets,
    required this.period,
  });

  final List<StatBucket> buckets;

  /// Which grid [buckets] were bucketed on.
  final StatsPeriod period;

  @override
  Widget build(BuildContext context) {
    final rates = [for (final bucket in buckets) lookupRatePer1k(bucket)];
    final runs = _contiguousRuns(rates);
    // With nothing anywhere to divide by there is no series at all — an empty
    // pair of axes would be noise, not a zero state.
    if (runs.isEmpty) return const SizedBox.shrink();

    final l10n = context.l10n;
    return StatsChartCard(
      title: l10n.statsLookupRateTitle,
      subtitle: l10n.statsLookupRateSubtitle,
      chartBuilder: (context, filled, duration) => LineChart(
        _chartData(context: context, runs: runs, filled: filled),
        duration: duration,
        curve: Curves.easeOutCubic,
      ),
    );
  }

  LineChartData _chartData({
    required BuildContext context,
    required List<List<FlSpot>> runs,
    required bool filled,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final rateFormat = NumberFormat('#,##0.0', locale);
    final seriesColor = chartSeriesColor(colors);

    final peak = runs.fold<double>(
      0,
      (top, run) => run.fold(top, (best, spot) => math.max(best, spot.y)),
    );
    final interval = niceInterval(peak);
    final step = axisLabelStep(buckets.length);

    return LineChartData(
      minX: 0,
      maxX: (buckets.length - 1).toDouble(),
      minY: 0,
      maxY: interval * 4,
      gridData: statsChartGrid(colors, interval),
      borderData: statsChartBorder(),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(),
        rightTitles: const AxisTitles(),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: chartLeftAxisWidth,
            interval: interval,
            getTitlesWidget: (value, meta) => value <= 0
                ? const SizedBox.shrink()
                : statsAxisLabel(context, meta, rateFormat.format(value)),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: chartBottomAxisHeight,
            interval: step.toDouble(),
            getTitlesWidget: (value, meta) {
              final index = value.round();
              if (index % step != 0 || index < 0 || index >= buckets.length) {
                return const SizedBox.shrink();
              }
              return statsAxisLabel(
                context,
                meta,
                bucketAxisLabel(buckets[index].start, period, locale),
              );
            },
          ),
        ),
      ),
      lineTouchData: LineTouchData(
        // The line is two pixels wide; the thing you have to hit is not.
        touchSpotThreshold: 24,
        getTouchedSpotIndicator: (barData, indicators) => [
          for (final _ in indicators)
            TouchedSpotIndicatorData(
              FlLine(color: colors.outlineVariant, strokeWidth: 1),
              FlDotData(
                getDotPainter: (spot, percent, bar, index) =>
                    FlDotCirclePainter(
                      radius: _touchDotRadius,
                      color: seriesColor,
                      strokeWidth: 2,
                      strokeColor: statsCardColor(theme),
                    ),
              ),
            ),
        ],
        touchTooltipData: statsLineTooltip(
          colors,
          getTooltipItems: (touchedSpots) => [
            for (final spot in touchedSpots)
              _tooltipItem(theme, locale, rateFormat, spot),
          ],
        ),
      ),
      lineBarsData: [
        for (final run in runs)
          LineChartBarData(
            spots: filled ? run : _collapsed(run),
            color: seriesColor,
            barWidth: _lineWidth,
            isStrokeCapRound: true,
            isStrokeJoinRound: true,
            // A run of one has no line to draw, so it shows as its own point.
            dotData: FlDotData(
              show: run.length == 1,
              getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                radius: _loneSpotRadius,
                color: seriesColor,
                strokeWidth: 0,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  seriesColor.withValues(alpha: 0.26),
                  seriesColor.withValues(alpha: 0),
                ],
              ),
            ),
          ),
      ],
    );
  }

  LineTooltipItem? _tooltipItem(
    ThemeData theme,
    String locale,
    NumberFormat rateFormat,
    LineBarSpot spot,
  ) {
    final index = spot.x.round();
    if (index < 0 || index >= buckets.length) return null;
    return LineTooltipItem(
      '${bucketTooltipLabel(buckets[index].start, period, locale)}\n',
      statsTooltipLabelStyle(theme),
      children: [
        TextSpan(
          text: rateFormat.format(spot.y),
          style: statsTooltipValueStyle(theme),
        ),
      ],
    );
  }
}

/// Every unbroken run of buckets that has a rate, as chart spots.
///
/// The x value is the bucket's index, so the runs stay registered against the
/// shared category axis however many of them there are.
List<List<FlSpot>> _contiguousRuns(List<double?> rates) {
  final runs = <List<FlSpot>>[];
  var current = <FlSpot>[];
  for (var index = 0; index < rates.length; index++) {
    final rate = rates[index];
    if (rate == null) {
      if (current.isNotEmpty) runs.add(current);
      current = <FlSpot>[];
      continue;
    }
    current.add(FlSpot(index.toDouble(), rate));
  }
  if (current.isNotEmpty) runs.add(current);
  return runs;
}

/// The entrance frame: every spot of a run stacked on its first one, so the
/// line unrolls left to right as fl_chart interpolates them apart.
List<FlSpot> _collapsed(List<FlSpot> run) =>
    List<FlSpot>.filled(run.length, run.first);
