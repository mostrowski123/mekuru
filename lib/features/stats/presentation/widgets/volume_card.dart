import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mekuru/features/stats/data/services/stats_aggregator.dart';
import 'package:mekuru/features/stats/presentation/widgets/stats_chart_card.dart';
import 'package:mekuru/l10n/l10n.dart';

/// Corner rounding on the tip of a bar.
const double _rodRadius = 4;

/// Share of a bucket's slot the bar itself fills.
const double _rodWidthFactor = 0.55;

/// Characters read per bucket, with the period's page count as a figure.
///
/// Pages are text and only text. They are a second measure on a different
/// scale, and the spec allows a chart exactly one axis — so putting them on
/// the right-hand side is not an option the card offers.
class VolumeCard extends StatelessWidget {
  const VolumeCard({super.key, required this.buckets, required this.period});

  final List<StatBucket> buckets;

  /// Which grid [buckets] were bucketed on.
  final StatsPeriod period;

  @override
  Widget build(BuildContext context) {
    if (buckets.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final l10n = context.l10n;
    final counts = NumberFormat.decimalPattern(
      Localizations.localeOf(context).toLanguageTag(),
    );
    final pages = buckets.fold<int>(0, (sum, b) => sum + b.pagesTurned);

    return StatsChartCard(
      title: l10n.statsHeroCharactersRead,
      headerFigure: pages == 0
          ? null
          : Text(
              l10n.statsVolumePageCount(count: pages),
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
      chartBuilder: (context, filled, duration) => LayoutBuilder(
        builder: (context, constraints) => BarChart(
          _chartData(
            context: context,
            filled: filled,
            counts: counts,
            width: constraints.maxWidth,
          ),
          duration: duration,
          curve: Curves.easeOutCubic,
        ),
      ),
    );
  }

  BarChartData _chartData({
    required BuildContext context,
    required bool filled,
    required NumberFormat counts,
    required double width,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final compact = NumberFormat.compact(locale: locale);
    final seriesColor = chartSeriesColor(colors);

    final peak = buckets.fold<double>(
      0,
      (top, bucket) => math.max(top, bucket.charactersRead.toDouble()),
    );
    final interval = niceInterval(peak);
    final step = axisLabelStep(buckets.length);
    final rodWidth =
        ((width - chartLeftAxisWidth) / buckets.length * _rodWidthFactor).clamp(
          2.0,
          18.0,
        );

    return BarChartData(
      maxY: interval * 4,
      minY: 0,
      alignment: BarChartAlignment.spaceAround,
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
                : statsAxisLabel(context, meta, compact.format(value)),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: chartBottomAxisHeight,
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
      barTouchData: BarTouchData(
        touchExtraThreshold: const EdgeInsets.symmetric(horizontal: 10),
        touchTooltipData: statsBarTooltip(
          colors,
          getTooltipItem: (group, groupIndex, rod, rodIndex) {
            if (groupIndex < 0 || groupIndex >= buckets.length) return null;
            final bucket = buckets[groupIndex];
            return BarTooltipItem(
              '${bucketTooltipLabel(bucket.start, period, locale)}\n',
              statsTooltipLabelStyle(theme),
              children: [
                TextSpan(
                  text: counts.format(bucket.charactersRead),
                  style: statsTooltipValueStyle(theme),
                ),
              ],
            );
          },
        ),
      ),
      barGroups: [
        for (var index = 0; index < buckets.length; index++)
          BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: filled ? buckets[index].charactersRead.toDouble() : 0,
                width: rodWidth,
                color: seriesColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(_rodRadius),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
