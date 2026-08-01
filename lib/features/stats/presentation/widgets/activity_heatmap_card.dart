import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mekuru/features/stats/data/services/stats_aggregator.dart';
import 'package:mekuru/l10n/l10n.dart';

/// Side of one day cell and the gap between two of them.
///
/// A year is 53 columns wide, so the grid overflows every phone and scrolls
/// horizontally; these are sized so a full year stays legible rather than so
/// it fits.
const double _cellSize = 11;
const double _cellGap = 3;
const double _cellPitch = _cellSize + _cellGap;
const double _gridHeight = _cellPitch * 7 - _cellGap;
const double _monthLabelHeight = 16;

/// Minutes at which each intensity step starts, lightest first.
const List<int> _stepThresholds = [1, 15, 30, 60];

/// Opacity of [ColorScheme.primary] for each step, lightest first.
///
/// One hue in four stops — the sequential ramp the spec asks for. Translucent
/// rather than pre-blended so the ramp composites over whatever surface the
/// card sits on, which is what keeps it correct in both themes without a
/// second set of colors.
const List<double> _stepOpacities = [0.24, 0.46, 0.72, 1];

/// Fraction of the entrance the diagonal wave's leading edge spans.
const double _waveWidth = 0.35;

/// Which intensity step [day] paints at, or null when the day is empty.
///
/// A day counts as active when *any* of minutes, characters or lookups is
/// non-zero: [HeatmapDay.minutes] floors, so ninety seconds of reading is zero
/// minutes but still a day the reader showed up. Those days clamp into the
/// lowest step; from there up the ramp is keyed on minutes alone.
@visibleForTesting
int? heatmapIntensityStep(HeatmapDay day) {
  for (var step = _stepThresholds.length - 1; step >= 0; step--) {
    if (day.minutes >= _stepThresholds[step]) return step;
  }
  return day.charactersRead > 0 || day.lookups > 0 ? 0 : null;
}

/// GitHub-style grid of the trailing twelve months, one cell per day, shaded
/// by how long that day was read for.
///
/// Always shows the whole year: the stats screen's period selector moves the
/// time-series cards, not this one. Tapping a cell reports the day through
/// [onDayTap] — the screen turns that into the day's detail sheet, so the card
/// stays a pure rendering of [days].
class ActivityHeatmapCard extends StatelessWidget {
  const ActivityHeatmapCard({
    super.key,
    required this.days,
    required this.onDayTap,
  });

  /// One entry per day, oldest first — the output of [heatmapDays].
  final List<HeatmapDay> days;

  /// Called with the day behind a tapped cell.
  final ValueChanged<HeatmapDay> onDayTap;

  /// Hook for tests that need to aim a tap at a specific cell.
  @visibleForTesting
  static const Key gridKey = ValueKey('activityHeatmapGrid');

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const SizedBox.shrink();

    // Weeks run down the columns, so the first day starts partway down column
    // zero and every later day is one step along from it.
    final leadingOffset = _rowOf(
      days.first.day,
      MaterialLocalizations.of(context).firstDayOfWeekIndex,
    );
    final columns = ((leadingOffset + days.length) / 7).ceil();

    final disableAnimations = MediaQuery.of(context).disableAnimations;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      // The card is built inside a plain Column, never a lazy list, so this
      // runs once per screen open and is not replayed by scrolling.
      builder: (context, t, _) =>
          Opacity(opacity: t, child: _card(context, leadingOffset, columns, t)),
    );
  }

  Widget _card(
    BuildContext context,
    int leadingOffset,
    int columns,
    double progress,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final fills = [
      for (final opacity in _stepOpacities)
        colors.primary.withValues(alpha: opacity),
    ];
    // Empty days are outlined, not filled: an unread day should read as an
    // empty slot on the surface rather than as a gray value on the ramp.
    final emptyOutline = colors.outlineVariant;
    final width = columns * _cellPitch - _cellGap;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.statsHeatmapTitle,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                // Opens on the most recent weeks; the year runs back off to
                // the left for anyone who wants it.
                reverse: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: width,
                      height: _monthLabelHeight,
                      child: Stack(
                        children: _monthLabels(context, leadingOffset, width),
                      ),
                    ),
                    GestureDetector(
                      key: gridKey,
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (details) =>
                          _tapCell(details.localPosition, leadingOffset),
                      child: CustomPaint(
                        size: Size(width, _gridHeight),
                        painter: _HeatmapPainter(
                          days: days,
                          leadingOffset: leadingOffset,
                          columns: columns,
                          fills: fills,
                          emptyOutline: emptyOutline,
                          progress: progress,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _Legend(fills: fills, emptyOutline: emptyOutline),
            ],
          ),
        ),
      ),
    );
  }

  /// A month abbreviation above the column each month starts in.
  List<Widget> _monthLabels(
    BuildContext context,
    int leadingOffset,
    double width,
  ) {
    final style = Theme.of(context).textTheme.labelSmall;
    final format = DateFormat.MMM(
      Localizations.localeOf(context).toLanguageTag(),
    );
    final labels = <Widget>[];
    for (var i = 0; i < days.length; i++) {
      if (days[i].day.day != 1) continue;
      final left = ((leadingOffset + i) ~/ 7) * _cellPitch;
      // A month opening in the last column or two has no room left for its
      // name, so pin that one to the end of the grid rather than clip it.
      final pinned = left > width - _cellPitch * 2;
      labels.add(
        Positioned(
          left: pinned ? null : left,
          right: pinned ? 0 : null,
          top: 0,
          child: Text(format.format(days[i].day), style: style),
        ),
      );
    }
    return labels;
  }

  /// Resolves a tap anywhere in the grid to the day it landed on.
  ///
  /// The whole pitch counts, gap included, so the tap target is a little
  /// larger than the cell it selects.
  void _tapCell(Offset position, int leadingOffset) {
    final column = position.dx ~/ _cellPitch;
    final row = position.dy ~/ _cellPitch;
    final index = column * 7 + row - leadingOffset;
    if (index < 0 || index >= days.length) return;
    onDayTap(days[index]);
  }
}

/// Which of the seven rows [day] lands on, given the locale's first weekday.
int _rowOf(DateTime day, int firstDayOfWeekIndex) =>
    (day.weekday % 7 - firstDayOfWeekIndex) % 7;

/// The "Less ▢▢▢▢ More" scale under the grid.
class _Legend extends StatelessWidget {
  const _Legend({required this.fills, required this.emptyOutline});

  final List<Color> fills;
  final Color emptyOutline;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final style = Theme.of(context).textTheme.labelSmall;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(l10n.statsHeatmapLegendLess, style: style),
        const SizedBox(width: 6),
        _swatch(outline: emptyOutline),
        for (final fill in fills) _swatch(fill: fill),
        const SizedBox(width: 6),
        Text(l10n.statsHeatmapLegendMore, style: style),
      ],
    );
  }

  Widget _swatch({Color? fill, Color? outline}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 1.5),
    child: Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: fill,
        border: outline == null ? null : Border.all(color: outline),
        borderRadius: const BorderRadius.all(Radius.circular(2)),
      ),
    ),
  );
}

/// Paints the year of cells: 365 rounded rects is far cheaper as one painter
/// than as 365 widgets, and it is the only way to give empty days an outline.
class _HeatmapPainter extends CustomPainter {
  const _HeatmapPainter({
    required this.days,
    required this.leadingOffset,
    required this.columns,
    required this.fills,
    required this.emptyOutline,
    required this.progress,
  });

  final List<HeatmapDay> days;
  final int leadingOffset;
  final int columns;
  final List<Color> fills;
  final Color emptyOutline;

  /// The entrance, 0 to 1. Cells resolve their own share of it, so they sweep
  /// in diagonally instead of all appearing together.
  final double progress;

  static const Radius _radius = Radius.circular(2);

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint();
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (var i = 0; i < days.length; i++) {
      final position = leadingOffset + i;
      final column = position ~/ 7;
      final row = position % 7;
      final cellProgress = _cellProgress(column, row);
      if (cellProgress <= 0) continue;

      final rect = Rect.fromLTWH(
        column * _cellPitch,
        row * _cellPitch,
        _cellSize,
        _cellSize,
      );
      final step = heatmapIntensityStep(days[i]);
      if (step == null) {
        // Inset by half the stroke so the 1px outline lands on the pixel grid
        // instead of straddling the cell edge.
        stroke.color = _faded(emptyOutline, cellProgress);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.deflate(0.5), _radius),
          stroke,
        );
      } else {
        fill.color = _faded(fills[step], cellProgress);
        canvas.drawRRect(RRect.fromRectAndRadius(rect, _radius), fill);
      }
    }
  }

  /// How far into its own fade the cell at ([column], [row]) is.
  ///
  /// The wave starts at the right-hand edge — the weeks the reader is actually
  /// looking at when the screen opens — and sweeps back through the year.
  double _cellProgress(int column, int row) {
    if (progress >= 1) return 1;
    // At least 6: build() returns early on no days, so there is always a
    // column, and the seven rows alone put the span past zero.
    final span = (columns - 1) + 6;
    final distance = ((columns - 1 - column) + row) / span;
    return ((progress * (1 + _waveWidth) - distance) / _waveWidth).clamp(0, 1);
  }

  Color _faded(Color color, double t) =>
      t >= 1 ? color : color.withValues(alpha: color.a * t);

  @override
  bool shouldRepaint(_HeatmapPainter old) =>
      old.progress != progress ||
      old.days != days ||
      old.leadingOffset != leadingOffset ||
      old.columns != columns ||
      old.emptyOutline != emptyOutline ||
      !listEquals(old.fills, fills);
}
