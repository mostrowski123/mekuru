import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:mekuru/features/stats/data/services/stats_aggregator.dart';
import 'package:mekuru/features/stats/presentation/widgets/stats_chart_card.dart';
import 'package:mekuru/l10n/l10n.dart';

/// Gap cut between the two stacked segments of a bar, in logical pixels.
const double _stackGap = 2;

/// Corner rounding on the tip of a bar.
const double _rodRadius = 4;

/// Share of a bucket's slot the bar itself fills.
const double _rodWidthFactor = 0.55;

/// Time read per bucket, EPUB and manga stacked into one bar each.
///
/// Takes the two formats as separate series rather than a pre-filtered one:
/// the colors are fixed to the format, so the card has to know which minutes
/// belong to which. The stats screen passes an empty list for a format the
/// filter has excluded, which is what collapses the chart to a single series.
class ReadingTimeCard extends StatelessWidget {
  const ReadingTimeCard({
    super.key,
    required this.epubBuckets,
    required this.mangaBuckets,
    required this.period,
    this.bestDay,
  });

  /// EPUB minutes per bucket, or empty when the filter excludes EPUB.
  final List<StatBucket> epubBuckets;

  /// Manga minutes per bucket, or empty when the filter excludes manga.
  final List<StatBucket> mangaBuckets;

  /// Which grid [epubBuckets] and [mangaBuckets] were bucketed on.
  final StatsPeriod period;

  /// The longest day ever recorded, from [bestDay]. Annotated when it happens
  /// to fall inside the window on screen; ignored otherwise.
  final StatBucket? bestDay;

  @override
  Widget build(BuildContext context) {
    final bars = _mergeByStart(epubBuckets, mangaBuckets);
    if (bars.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = context.l10n;
    final epubColor = epubSeriesColor(colors);
    final mangaColor = mangaSeriesColor(colors);

    // Two series are only worth stacking — and only worth a legend — when
    // both of them actually have time in them.
    final stacked = _hasTime(epubBuckets) && _hasTime(mangaBuckets);
    // Which format a one-color chart belongs to. The filter decides first — it
    // hands the card nothing at all for a format it excluded — and the data
    // only breaks the tie inside the All view.
    final soloIsManga = epubBuckets.isEmpty
        ? mangaBuckets.isNotEmpty
        : _hasTime(mangaBuckets) && !_hasTime(epubBuckets);
    final soloColor = soloIsManga ? mangaColor : epubColor;

    return StatsChartCard(
      title: l10n.statsHeroReadingTime,
      legend: stacked
          ? StatsChartLegend(
              entries: [
                StatsLegendEntry(color: epubColor, label: l10n.statsFormatEpub),
                StatsLegendEntry(
                  color: mangaColor,
                  label: l10n.statsFormatManga,
                ),
              ],
            )
          : null,
      chartBuilder: (context, filled, duration) => LayoutBuilder(
        builder: (context, constraints) => BarChart(
          _chartData(
            context: context,
            bars: bars,
            filled: filled,
            stacked: stacked,
            soloColor: soloColor,
            epubColor: epubColor,
            mangaColor: mangaColor,
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
    required List<_Bar> bars,
    required bool filled,
    required bool stacked,
    required Color soloColor,
    required Color epubColor,
    required Color mangaColor,
    required double width,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toLanguageTag();

    final peak = bars.fold<double>(0, (top, bar) => math.max(top, bar.minutes));
    final interval = niceInterval(peak);
    final marked = _markedIndex(bars);
    // The best-day label is painted above the bar's tip, so the tallest bar
    // needs somewhere to put it when the peak lands exactly on a gridline.
    final needsHeadroom = marked != null && interval * 4 - peak < interval / 2;
    final maxY = interval * (needsHeadroom ? 5 : 4);

    final step = axisLabelStep(bars.length);
    final rodWidth =
        ((width - chartLeftAxisWidth) / bars.length * _rodWidthFactor).clamp(
          2.0,
          18.0,
        );
    // A bar's segments are cut apart by a border in the card's own color, so
    // the gap reads as the card showing through rather than as an outline.
    final gap = BorderSide(color: statsCardColor(theme), width: _stackGap);

    return BarChartData(
      maxY: maxY,
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
                : statsAxisLabel(context, meta, _axisDuration(value)),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: chartBottomAxisHeight,
            getTitlesWidget: (value, meta) {
              final index = value.round();
              if (index % step != 0 || index < 0 || index >= bars.length) {
                return const SizedBox.shrink();
              }
              return statsAxisLabel(
                context,
                meta,
                bucketAxisLabel(bars[index].start, period, locale),
              );
            },
          ),
        ),
      ),
      barTouchData: BarTouchData(
        // A finger is wider than a bar this thin, so the hit box is not.
        touchExtraThreshold: const EdgeInsets.symmetric(horizontal: 10),
        touchTooltipData: BarTouchTooltipData(
          getTooltipColor: (_) => statsTooltipColor(colors),
          maxContentWidth: 180,
          getTooltipItem: (group, groupIndex, rod, rodIndex) {
            if (groupIndex < 0 || groupIndex >= bars.length) return null;
            final bar = bars[groupIndex];
            final valueStyle = statsTooltipValueStyle(theme);
            return BarTooltipItem(
              '${bucketTooltipLabel(bar.start, period, locale)}\n',
              statsTooltipLabelStyle(theme),
              children: stacked
                  ? [
                      TextSpan(
                        text:
                            '${l10n.statsFormatEpub} '
                            '${formatDuration(bar.epubMs)}\n',
                        style: valueStyle,
                      ),
                      TextSpan(
                        text:
                            '${l10n.statsFormatManga} '
                            '${formatDuration(bar.mangaMs)}',
                        style: valueStyle,
                      ),
                    ]
                  : [
                      TextSpan(
                        text: formatDuration(bar.totalMs),
                        style: valueStyle,
                      ),
                    ],
            );
          },
        ),
      ),
      barGroups: [
        for (var index = 0; index < bars.length; index++)
          BarChartGroupData(
            x: index,
            barRods: [
              _rod(
                bar: bars[index],
                filled: filled,
                stacked: stacked,
                soloColor: soloColor,
                epubColor: epubColor,
                mangaColor: mangaColor,
                gap: gap,
                width: rodWidth,
                label: index == marked
                    ? BarChartRodLabel(
                        show: filled,
                        text: l10n.statsBestDayMarker,
                        style: statsTooltipLabelStyle(theme),
                        offset: const Offset(0, 6),
                      )
                    : const BarChartRodLabel(show: false),
              ),
            ],
          ),
      ],
    );
  }

  BarChartRodData _rod({
    required _Bar bar,
    required bool filled,
    required bool stacked,
    required Color soloColor,
    required Color epubColor,
    required Color mangaColor,
    required BorderSide gap,
    required double width,
    required BarChartRodLabel label,
  }) {
    // The entrance frame is the same chart with every value at the baseline;
    // fl_chart grows the bars from there.
    final epub = filled ? bar.epubMs / Duration.millisecondsPerMinute : 0.0;
    final total = filled ? bar.minutes : 0.0;
    return BarChartRodData(
      toY: total,
      width: width,
      color: stacked ? epubColor : soloColor,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(_rodRadius),
      ),
      label: label,
      rodStackItems: stacked
          ? [
              BarChartRodStackItem(0, epub, epubColor),
              BarChartRodStackItem(epub, total, mangaColor, borderSide: gap),
            ]
          : const [],
    );
  }

  /// Which bar carries the best-day annotation, or null when none does.
  ///
  /// Only day buckets can: on the year and all-time grids a bar is a whole
  /// month, and labelling a month "best day" would be a claim the chart is not
  /// making.
  int? _markedIndex(List<_Bar> bars) {
    final best = bestDay;
    if (best == null) return null;
    if (period != StatsPeriod.week && period != StatsPeriod.month) return null;
    final index = bars.indexWhere((bar) => bar.start == best.start);
    return index < 0 ? null : index;
  }
}

/// One bar: both formats' time for the same bucket.
class _Bar {
  const _Bar({
    required this.start,
    required this.epubMs,
    required this.mangaMs,
  });

  final DateTime start;
  final int epubMs;
  final int mangaMs;

  int get totalMs => epubMs + mangaMs;

  double get minutes => totalMs / Duration.millisecondsPerMinute;
}

/// Pairs the two series up by bucket start rather than by index.
///
/// [StatsPeriod.all] starts its grid at the first *matching* session's month,
/// so the EPUB and manga grids can begin in different months and line up
/// nowhere. Keying on the start instant makes the union the full period either
/// way.
List<_Bar> _mergeByStart(List<StatBucket> epub, List<StatBucket> manga) {
  final byStart = <DateTime, ({int epubMs, int mangaMs})>{};
  for (final bucket in epub) {
    byStart[bucket.start] = (epubMs: bucket.durationMs, mangaMs: 0);
  }
  for (final bucket in manga) {
    final existing = byStart[bucket.start];
    byStart[bucket.start] = (
      epubMs: existing?.epubMs ?? 0,
      mangaMs: bucket.durationMs,
    );
  }
  final starts = byStart.keys.toList()..sort();
  return [
    for (final start in starts)
      _Bar(
        start: start,
        epubMs: byStart[start]!.epubMs,
        mangaMs: byStart[start]!.mangaMs,
      ),
  ];
}

bool _hasTime(List<StatBucket> buckets) =>
    buckets.any((bucket) => bucket.durationMs > 0);

/// Axis ticks for a minutes scale: `"30m"`, `"1h"`, `"1.5h"`.
///
/// Deliberately terser than [formatDuration] — `"1h 30m"` on every gridline
/// would shout louder than the bars.
String _axisDuration(double minutes) {
  if (minutes < Duration.minutesPerHour) return '${minutes.round()}m';
  final hours = minutes / Duration.minutesPerHour;
  return hours == hours.roundToDouble()
      ? '${hours.round()}h'
      : '${hours.toStringAsFixed(1)}h';
}
