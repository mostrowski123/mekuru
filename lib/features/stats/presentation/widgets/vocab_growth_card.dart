import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mekuru/features/stats/data/services/stats_aggregator.dart';
import 'package:mekuru/features/stats/presentation/widgets/stats_chart_card.dart';
import 'package:mekuru/l10n/l10n.dart';

/// Gap between the end of the curve and its direct label.
const double _endLabelGap = 6;

/// Cumulative distinct expressions over the selected period.
///
/// The curve only ever climbs, and its last value is direct-labelled where the
/// line ends rather than left to the axis to imply.
class VocabGrowthCard extends StatelessWidget {
  const VocabGrowthCard({
    super.key,
    required this.points,
    required this.windowStart,
    required this.windowEnd,
  });

  /// The full cumulative curve from [cumulativeUniqueWords] — sparse, and
  /// ending at the last day a new expression turned up.
  final List<CumulativePoint> points;

  /// First instant the selected period covers, or null for all-time.
  final DateTime? windowStart;

  /// Last instant the selected period covers — normally now.
  final DateTime windowEnd;

  @override
  Widget build(BuildContext context) {
    final domain = vocabGrowthDomain(points, windowStart, windowEnd);
    final total = domain.spots.isEmpty ? 0.0 : domain.spots.last.y;
    // One point is a dot, not a curve, and a curve pinned at zero is a reader
    // who has saved nothing yet — a flat line along the axis says that worse
    // than an absent card does. Totals only ever climb, so a zero end means
    // zero everywhere.
    if (domain.spots.length < 2 || total <= 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final l10n = context.l10n;
    final counts = NumberFormat.decimalPattern(
      Localizations.localeOf(context).toLanguageTag(),
    );
    final interval = niceInterval(total);
    final maxY = interval * 4;

    return StatsChartCard(
      title: l10n.statsVocabGrowthTitle,
      chartBuilder: (context, filled, duration) => Stack(
        fit: StackFit.expand,
        children: [
          LineChart(
            _chartData(
              context: context,
              domain: domain,
              interval: interval,
              maxY: maxY,
              filled: filled,
              counts: counts,
            ),
            duration: duration,
            curve: Curves.easeOutCubic,
          ),
          // The curve is monotonic, so its end is always its highest point:
          // the label rides just above where the line stops on the right.
          Positioned(
            right: 0,
            bottom: _endLabelBottom(total, maxY),
            child: AnimatedOpacity(
              opacity: filled ? 1 : 0,
              duration: duration,
              child: Text(
                counts.format(total.round()),
                style: statsTooltipValueStyle(theme),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Where the end label sits above the plot floor, in logical pixels.
  double _endLabelBottom(double total, double maxY) {
    final plotHeight = chartPlotHeight - chartBottomAxisHeight;
    final atLine = plotHeight * (total / maxY);
    // Never let the label ride off the top of the card.
    return (chartBottomAxisHeight + atLine + _endLabelGap).clamp(
      0.0,
      chartPlotHeight - 20,
    );
  }

  LineChartData _chartData({
    required BuildContext context,
    required VocabGrowthDomain domain,
    required double interval,
    required double maxY,
    required bool filled,
    required NumberFormat counts,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final seriesColor = chartSeriesColor(colors);
    final spots = domain.spots;
    final lastX = spots.last.x;
    final labelInterval = (lastX / 4).ceilToDouble().clamp(
      1.0,
      double.infinity,
    );

    return LineChartData(
      minX: 0,
      maxX: lastX,
      minY: 0,
      maxY: maxY,
      gridData: statsChartGrid(colors, interval),
      borderData: statsChartBorder(),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(),
        rightTitles: const AxisTitles(),
        leftTitles: statsValueAxis(
          context,
          interval,
          (value) => counts.format(value.round()),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: chartBottomAxisHeight,
            interval: labelInterval,
            getTitlesWidget: (value, meta) => statsAxisLabel(
              context,
              meta,
              DateFormat.Md(locale).format(domain.dayAt(value)),
            ),
          ),
        ),
      ),
      lineTouchData: LineTouchData(
        touchSpotThreshold: 24,
        getTouchedSpotIndicator: statsLineTouchIndicator(theme, seriesColor),
        touchTooltipData: statsLineTooltip(
          colors,
          getTooltipItems: (touchedSpots) => [
            for (final spot in touchedSpots)
              LineTooltipItem(
                '${DateFormat.yMMMd(locale).format(domain.dayAt(spot.x))}\n',
                statsTooltipLabelStyle(theme),
                children: [
                  TextSpan(
                    text: context.l10n.statsVocabWordCount(
                      count: spot.y.round(),
                    ),
                    style: statsTooltipValueStyle(theme),
                  ),
                ],
              ),
          ],
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: filled ? spots : collapsedSpots(spots),
          color: seriesColor,
          barWidth: statsLineWidth,
          isStrokeCapRound: true,
          isStrokeJoinRound: true,
          dotData: const FlDotData(show: false),
          belowBarData: statsLineFill(seriesColor),
        ),
      ],
    );
  }
}

/// The curve to plot, plus the day its x axis is measured from.
@immutable
@visibleForTesting
class VocabGrowthDomain {
  const VocabGrowthDomain({required this.start, required this.spots});

  /// The day `x == 0` means.
  final DateTime start;

  /// The curve, x in days since [start].
  final List<FlSpot> spots;

  /// The day an x value falls on.
  DateTime dayAt(double x) =>
      DateTime(start.year, start.month, start.day + x.round());
}

/// Turns [cumulativeUniqueWords]' sparse output into a curve that spans the
/// whole selected window.
///
/// Two things have to happen for the rendered curve to tell the truth:
///
/// * The series **stops at the last new word**, which on its own would make
///   the line die halfway across the card and read as if the count had
///   collapsed. So the last total is carried forward to [windowEnd] as a
///   synthetic terminal point.
/// * Expressions first seen **before** [windowStart] are still known, they
///   just were not learned here. They are dropped from the curve but their
///   running total is carried into its first value, so the window opens at the
///   level the reader had already reached rather than at zero.
@visibleForTesting
VocabGrowthDomain vocabGrowthDomain(
  List<CumulativePoint> points,
  DateTime? windowStart,
  DateTime windowEnd,
) {
  final start = windowStart ?? (points.isEmpty ? windowEnd : points.first.day);
  final startDay = DateTime(start.year, start.month, start.day);

  var carried = 0;
  final visible = <CumulativePoint>[];
  for (final point in points) {
    if (point.day.isBefore(startDay)) {
      carried = point.total;
      continue;
    }
    if (point.day.isAfter(windowEnd)) break;
    visible.add(point);
  }

  // Whole days, so a DST transition inside the window cannot shift a point
  // onto the wrong tick.
  double x(DateTime day) => DateTime(
    day.year,
    day.month,
    day.day,
  ).difference(startDay).inDays.toDouble();

  final spots = <FlSpot>[];
  if (visible.isEmpty || x(visible.first.day) > 0) {
    spots.add(FlSpot(0, carried.toDouble()));
  }
  for (final point in visible) {
    spots.add(FlSpot(x(point.day), point.total.toDouble()));
  }
  final endX = x(windowEnd);
  if (spots.isNotEmpty && endX > spots.last.x) {
    spots.add(FlSpot(endX, spots.last.y));
  }

  return VocabGrowthDomain(start: startDay, spots: spots);
}
