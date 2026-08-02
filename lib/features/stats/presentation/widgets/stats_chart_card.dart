import 'dart:math' as math;
// intl also exports a TextDirection; the painter below needs the ui one.
import 'dart:ui' as ui show TextDirection;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mekuru/features/stats/data/services/stats_aggregator.dart';

/// How long fl_chart spends growing bars / drawing lines into place.
///
/// The spec's whole entrance sequence is ~600ms; the hero tiles take the first
/// ~400ms of it, so the charts land alongside them rather than after.
const Duration chartAnimationDuration = Duration(milliseconds: 400);

/// Height every card gives its plot area, axis labels included.
const double chartPlotHeight = 172;

/// Estimate of the value axis' width, used only for bar-width arithmetic.
///
/// The width actually reserved is measured from the tick labels per chart in
/// [statsValueAxis]; this stays a round upper bound so the bar-width clamp in
/// [statsRodWidth] does not need the measurement threaded through to it.
const double chartLeftAxisWidth = 44;

/// Room reserved for the category axis.
const double chartBottomAxisHeight = 24;

/// The color EPUB reading is drawn in, on every stats chart, forever.
///
/// Format identity is fixed to the hue: filtering to Manga does not promote
/// manga onto this color, and filtering to EPUB does not move EPUB off it.
Color epubSeriesColor(ColorScheme colors) => colors.primary;

/// The color manga reading is drawn in, on every stats chart, forever.
///
/// A *snapped* tertiary shade rather than [ColorScheme.tertiary] itself. The
/// spec requires the format pair to be checked with the dataviz validator
/// rather than eyeballed, and raw `primary`/`tertiary` fails it badly in both
/// themes — Material 3 puts tertiary only 60° off the seed hue at the same
/// tone, so the two collapse into each other (mekuruRed light: ΔE 2.2 under
/// deuteranopia, 8.2 with full color vision; dark: 3.4 / 8.0, both far under
/// the 15 floor). Sliding the tone 40% toward `tertiaryContainer` keeps the
/// tertiary hue — the identity the spec fixes — while separating the pair on
/// lightness: ΔE ≥ 14.1 simulated and ≥ 17.3 normal across all nine seed
/// themes in both brightnesses.
Color mangaSeriesColor(ColorScheme colors) =>
    Color.lerp(colors.tertiary, colors.tertiaryContainer, _mangaToneShift)!;

/// How far the manga shade slides off [ColorScheme.tertiary] toward its
/// container. Tuned to the smallest step that clears the validator's CVD and
/// normal-vision floors in every theme without dropping the mark's contrast
/// against the card below ~2.8:1.
const double _mangaToneShift = 0.4;

/// The color the single-series charts (volume, lookup rate, vocab growth) draw
/// in.
///
/// Deliberately *not* the format colors: those two carry the EPUB-vs-manga
/// distinction on the one chart that shows both at once, and re-tinting the
/// other three as the filter moves would turn a fixed identity into a
/// decoration.
Color chartSeriesColor(ColorScheme colors) => colors.primary;

/// Builds a card's chart.
///
/// [filled] is false on the entrance frame and true from the next one, which
/// is what makes fl_chart animate; [duration] is already zero when the
/// platform asks for reduced motion.
typedef ChartBuilder =
    Widget Function(BuildContext context, bool filled, Duration duration);

/// The shell every stats chart card is built in: one `Card`, one title, an
/// optional subtitle, an optional header figure, a fixed-height plot and an
/// optional legend underneath.
///
/// Also owns the entrance the spec asks for, once, on behalf of all four
/// cards: the first frame builds the chart with zero-valued data, a
/// post-frame callback swaps in the real values, and fl_chart's implicit
/// animation interpolates between the two — bars grow off the baseline, lines
/// unroll. The same mechanism covers period and format switches for free,
/// since those are just another data change.
class StatsChartCard extends StatefulWidget {
  const StatsChartCard({
    super.key,
    required this.title,
    required this.chartBuilder,
    this.subtitle,
    this.headerFigure,
    this.legend,
  });

  final String title;

  /// Builds the plot. See [ChartBuilder].
  final ChartBuilder chartBuilder;

  /// One quiet line under the title, for a chart whose unit needs explaining.
  final String? subtitle;

  /// A figure shown at the end of the title row — the spec's escape hatch for
  /// a second measure that must never become a second axis.
  final Widget? headerFigure;

  /// Shown under the plot. Only for charts that actually draw two series.
  final Widget? legend;

  @override
  State<StatsChartCard> createState() => _StatsChartCardState();
}

class _StatsChartCardState extends State<StatsChartCard> {
  bool _filled = false;

  @override
  void initState() {
    super.initState();
    // The card lives in a plain Column, never a lazy list, so this runs once
    // per screen open rather than every time it scrolls back into view.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _filled = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    // With motion off the chart is whole from the first frame: there is no
    // animation left for the zero-valued frame to start, so drawing it would
    // just be a flash of an empty plot.
    final filled = _filled || disableAnimations;
    final duration = disableAnimations ? Duration.zero : chartAnimationDuration;

    return Padding(
      // 16 horizontal, matching the hero row and control row above: the page
      // keeps one left margin rather than staggering bare content and cards.
      // The Card's own default 4dp margin is zeroed for the same reason — its
      // face, not its box, is what has to sit on that line.
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  if (widget.headerFigure != null) widget.headerFigure!,
                ],
              ),
              if (widget.subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  widget.subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                height: chartPlotHeight,
                child: widget.chartBuilder(context, filled, duration),
              ),
              if (widget.legend != null) ...[
                const SizedBox(height: 10),
                widget.legend!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One series' entry in a chart legend.
class StatsLegendEntry {
  const StatsLegendEntry({required this.color, required this.label});

  final Color color;
  final String label;
}

/// A compact colored-dot legend.
///
/// The label is always ink, never the series color: the dot beside it is what
/// carries the identity.
class StatsChartLegend extends StatelessWidget {
  const StatsChartLegend({super.key, required this.entries});

  final List<StatsLegendEntry> entries;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium;
    return Row(
      children: [
        for (final entry in entries) ...[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: entry.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(entry.label, style: style),
          const SizedBox(width: 16),
        ],
      ],
    );
  }
}

/// The recessive grid the spec asks for: thin horizontal rules only, no
/// vertical lines, no chart border.
FlGridData statsChartGrid(ColorScheme colors, double interval) => FlGridData(
  drawVerticalLine: false,
  horizontalInterval: interval,
  getDrawingHorizontalLine: (_) =>
      FlLine(color: colors.outlineVariant, strokeWidth: 1),
);

/// Charts are bounded by their gridlines, not by a box.
FlBorderData statsChartBorder() => FlBorderData(show: false);

/// One axis tick label, in ink rather than in the series color.
Widget statsAxisLabel(BuildContext context, TitleMeta meta, String text) {
  final theme = Theme.of(context);
  return SideTitleWidget(
    meta: meta,
    child: Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

/// Gap between a tick label and the plot: [SideTitleWidget]'s own 8px spacing
/// plus a little air so the measured reservation never clips a glyph.
const double _valueAxisGap = 12;

/// The value axis every stats chart draws on its left.
///
/// [label] renders one tick's value. Zero is never labelled: the axis meets the
/// baseline there, and a "0" under it reads as data rather than as the origin.
///
/// The reserved width is measured from the tick labels themselves rather than
/// fixed: a chart whose widest label is "25m" would otherwise hold a band of
/// dead space between the card's edge and the plot. [lines] is how many ticks
/// the chart draws — its maxY over [interval].
AxisTitles statsValueAxis(
  BuildContext context,
  double interval,
  String Function(double value) label, {
  int lines = 4,
}) {
  final style = Theme.of(context).textTheme.bodySmall;
  final scaler = MediaQuery.textScalerOf(context);
  var widest = 0.0;
  for (var line = 1; line <= lines; line++) {
    final painter = TextPainter(
      text: TextSpan(text: label(interval * line), style: style),
      textDirection: ui.TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    widest = math.max(widest, painter.width);
    painter.dispose();
  }
  return AxisTitles(
    sideTitles: SideTitles(
      showTitles: true,
      reservedSize: widest + _valueAxisGap,
      interval: interval,
      getTitlesWidget: (value, meta) => value <= 0
          ? const SizedBox.shrink()
          : statsAxisLabel(context, meta, label(value)),
    ),
  );
}

/// The category axis under a bucketed chart: one tick per bucket start, thinned
/// to every [step]th so the labels never collide.
///
/// [interval] is fl_chart's own tick spacing and is deliberately separate from
/// [step] — a chart whose x values are bucket indices needs both told to it,
/// while one that lets fl_chart choose its own ticks passes null and relies on
/// the modulo guard alone.
AxisTitles statsBucketAxis(
  BuildContext context,
  List<DateTime> starts,
  int step,
  StatsPeriod period,
  String locale, {
  double? interval,
}) => AxisTitles(
  sideTitles: SideTitles(
    showTitles: true,
    reservedSize: chartBottomAxisHeight,
    interval: interval,
    getTitlesWidget: (value, meta) {
      final index = value.round();
      if (index % step != 0 || index < 0 || index >= starts.length) {
        return const SizedBox.shrink();
      }
      return statsAxisLabel(
        context,
        meta,
        bucketAxisLabel(starts[index], period, locale),
      );
    },
  ),
);

/// Background of a touch tooltip.
Color _statsTooltipColor(ColorScheme colors) => colors.surfaceContainerHighest;

/// The edge that lifts a tooltip off whatever it is covering.
///
/// Not decoration: the dark theme repaints cards in `surfaceContainerHighest`
/// as well, so an unbordered tooltip in the color above would be an invisible
/// rectangle sitting on a card of the identical color. The outline is what
/// makes it read as a popover in both themes.
BorderSide _statsTooltipBorder(ColorScheme colors) =>
    BorderSide(color: colors.outlineVariant);

/// A bar chart's touch tooltip, styled the way every stats chart's is.
BarTouchTooltipData statsBarTooltip(
  ColorScheme colors, {
  required GetBarTooltipItem getTooltipItem,
  double? maxContentWidth,
}) => BarTouchTooltipData(
  getTooltipColor: (_) => _statsTooltipColor(colors),
  tooltipBorder: _statsTooltipBorder(colors),
  maxContentWidth: maxContentWidth,
  getTooltipItem: getTooltipItem,
);

/// A line chart's touch tooltip, styled the way every stats chart's is.
LineTouchTooltipData statsLineTooltip(
  ColorScheme colors, {
  required GetLineTooltipItems getTooltipItems,
}) => LineTouchTooltipData(
  getTooltipColor: (_) => _statsTooltipColor(colors),
  tooltipBorder: _statsTooltipBorder(colors),
  getTooltipItems: getTooltipItems,
);

/// What a card is actually painted on, so a mark can cut a gap out of itself.
///
/// The dark theme repaints cards in `surfaceContainerHighest`; the light theme
/// leaves the Material 3 default in place.
Color statsCardColor(ThemeData theme) =>
    theme.cardTheme.color ?? theme.colorScheme.surfaceContainerLow;

/// Tooltip caption — the bucket a touched mark belongs to.
TextStyle statsTooltipLabelStyle(ThemeData theme) =>
    (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

/// Tooltip figure — the exact value behind a touched mark.
TextStyle statsTooltipValueStyle(ThemeData theme) =>
    (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
      color: theme.colorScheme.onSurface,
      fontWeight: FontWeight.w700,
    );

/// Stroke width of a trend line.
const double statsLineWidth = 2;

/// Radius of the dot under a finger. Ten logical pixels across, so the mark the
/// tooltip refers to is never smaller than the thing that summoned it.
const double _touchDotRadius = 5;

/// The mark fl_chart paints on a touched spot: a hairline down to the axis and
/// a dot in [seriesColor], ringed in the card's own color so it reads as
/// sitting on top of the line rather than as a bead threaded onto it.
GetTouchedSpotIndicator statsLineTouchIndicator(
  ThemeData theme,
  Color seriesColor,
) =>
    (barData, indicators) => [
      for (final _ in indicators)
        TouchedSpotIndicatorData(
          FlLine(color: theme.colorScheme.outlineVariant, strokeWidth: 1),
          FlDotData(
            getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
              radius: _touchDotRadius,
              color: seriesColor,
              strokeWidth: 2,
              strokeColor: statsCardColor(theme),
            ),
          ),
        ),
    ];

/// The wash under a trend line: the series color fading out downward, so the
/// curve reads as a level rather than as a bare stroke.
BarAreaData statsLineFill(Color seriesColor) => BarAreaData(
  show: true,
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      seriesColor.withValues(alpha: 0.26),
      seriesColor.withValues(alpha: 0),
    ],
  ),
);

/// The entrance frame of a line: every spot stacked on the first one, so the
/// line unrolls left to right as fl_chart interpolates them apart.
List<FlSpot> collapsedSpots(List<FlSpot> spots) =>
    List<FlSpot>.filled(spots.length, spots.first);

/// Corner rounding on the tip of a bar.
const double _rodRadius = 4;

/// The rounded tip every stats bar is drawn with.
const BorderRadius statsRodTopRadius = BorderRadius.vertical(
  top: Radius.circular(_rodRadius),
);

/// Share of a bucket's slot the bar itself fills.
const double _rodWidthFactor = 0.55;

/// How wide one bar is drawn, given the plot's full [chartWidth] and how many
/// bars share it.
///
/// Clamped at both ends: a week of bars would otherwise be slabs, and a year of
/// them would thin out below a visible line.
double statsRodWidth(double chartWidth, int barCount) =>
    ((chartWidth - chartLeftAxisWidth) / barCount * _rodWidthFactor).clamp(
      2.0,
      18.0,
    );

/// A gridline step that lands on round numbers and gives roughly [lines]
/// intervals below [maxValue].
///
/// Charts then take `interval * lines` as their axis maximum, which is always
/// at or above the peak and usually a little over it — the headroom a bar's
/// annotation needs.
double niceInterval(double maxValue, {int lines = 4}) {
  if (!maxValue.isFinite || maxValue <= 0) return 1;
  final raw = maxValue / lines;
  final magnitude = math
      .pow(10, (math.log(raw) / math.ln10).floor())
      .toDouble();
  for (final step in const [1.0, 2.0, 2.5, 5.0]) {
    if (step * magnitude >= raw) return step * magnitude;
  }
  return 10 * magnitude;
}

/// How many categories to skip between axis labels so that at most
/// [maxLabels] of [count] are drawn.
///
/// [StatsPeriod.all] can hand a chart years of month buckets, so the labels
/// thin out by arithmetic rather than by overlapping into each other.
int axisLabelStep(int count, {int maxLabels = 7}) =>
    count <= maxLabels ? 1 : (count / maxLabels).ceil();

/// The tick label under a bucket: a short date for day buckets, a month name
/// for month buckets.
String bucketAxisLabel(
  DateTime start,
  StatsPeriod period,
  String locale,
) => switch (period) {
  StatsPeriod.week || StatsPeriod.month => DateFormat.Md(locale).format(start),
  StatsPeriod.year || StatsPeriod.all => DateFormat.MMM(locale).format(start),
};

/// The bucket caption inside a tooltip — spelled out, since there is room.
String bucketTooltipLabel(DateTime start, StatsPeriod period, String locale) =>
    switch (period) {
      StatsPeriod.week ||
      StatsPeriod.month => DateFormat.yMMMd(locale).format(start),
      StatsPeriod.year ||
      StatsPeriod.all => DateFormat.yMMM(locale).format(start),
    };
