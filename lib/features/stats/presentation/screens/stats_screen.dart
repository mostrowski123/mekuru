import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mekuru/features/stats/data/services/stats_aggregator.dart';
import 'package:mekuru/features/stats/presentation/providers/stats_providers.dart';
import 'package:mekuru/features/stats/presentation/stats_formatting.dart';
import 'package:mekuru/features/stats/presentation/widgets/activity_heatmap_card.dart';
import 'package:mekuru/features/stats/presentation/widgets/hero_stat_tile.dart';
import 'package:mekuru/features/stats/presentation/widgets/lookup_rate_card.dart';
import 'package:mekuru/features/stats/presentation/widgets/reading_time_card.dart';
import 'package:mekuru/features/stats/presentation/widgets/vocab_growth_card.dart';
import 'package:mekuru/features/stats/presentation/widgets/volume_card.dart';
import 'package:mekuru/l10n/l10n.dart';

/// Reading statistics: headline numbers first, then the filters, then the
/// chart cards.
///
/// Every figure on the page is derived once here and handed down as a concrete
/// value. The cards are pure renderers of what they are given: none of them
/// reads a provider, and none of them re-derives a bucket grid the tile above
/// it already built.
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionsProvider);
    final events = ref.watch(wordEventsProvider);
    final sessionRows = sessions.value;
    final eventRows = events.value;

    if (sessionRows == null || eventRows == null) {
      // Nothing data-driven is rendered until both streams land, so the hero
      // count-up runs once with the real numbers instead of animating to zero
      // and then cutting. A stream that failed outright says so; the selectors
      // stay usable either way.
      return _page(context, [
        if (sessions.hasError || events.hasError)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              context.l10n.statsUnavailable,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        const SizedBox(height: 20),
        const _ControlRow(),
        const SizedBox(height: 8),
      ]);
    }

    final format = ref.watch(selectedStatsFormatProvider);
    final period = ref.watch(selectedStatsPeriodProvider);
    // One clock for the whole page. Read per card, these could land either
    // side of midnight and put the heatmap on a different day from the bars.
    final now = DateTime.now();

    final filteredSessions = filterSessions(sessionRows, format);
    final filteredEvents = filterWordEvents(eventRows, format);
    final buckets = bucketize(filteredSessions, period, now);
    final cumulativePoints = cumulativeUniqueWords(filteredEvents);

    return _page(context, [
      // Hero numbers come before any chart: the spec's reward surface leads
      // with typography, not with axes.
      _HeroStatsRow(
        totals: periodTotals(
          sessions: filteredSessions,
          events: filteredEvents,
          period: period,
          now: now,
        ),
      ),
      const SizedBox(height: 20),
      const _ControlRow(),
      const SizedBox(height: 8),
      // Chart cards land below, in spec order.
      //
      // The trailing year of activity, one cell per day. Deliberately built
      // from the format-filtered sessions but *not* the period selector: the
      // heatmap is the year view, and shrinking it to the selected window
      // would leave the screen with two competing time axes.
      ActivityHeatmapCard(
        days: heatmapDays(filteredSessions, now),
        onDayTap: (day) => _showDayDetail(context, day),
      ),
      // Time read per bucket, EPUB and manga stacked apart in the All view.
      // Each format is bucketed on its own grid so the card can color the two
      // apart; the filter drops a series by handing the card nothing for it.
      ReadingTimeCard(
        epubBuckets: format == StatsFormat.manga
            ? const []
            : bucketize(
                filterSessions(sessionRows, StatsFormat.epub),
                period,
                now,
              ),
        mangaBuckets: format == StatsFormat.epub
            ? const []
            : bucketize(
                filterSessions(sessionRows, StatsFormat.manga),
                period,
                now,
              ),
        period: period,
        // All-time, not window-limited: the card only annotates it when the
        // day happens to fall inside the window on screen.
        bestDay: bestDay(filteredSessions, now),
      ),
      // Characters read per bucket, with the period's pages as a header figure.
      VolumeCard(buckets: buckets, period: period),
      // Lookups per 1,000 characters, as a trend line with gaps.
      LookupRateCard(buckets: buckets, period: period),
      // Cumulative distinct expressions over the selected window.
      VocabGrowthCard(
        points: cumulativePoints,
        // Read off the same bucket grid the other cards use, so the curve and
        // the bars cover the same days.
        windowStart: windowStart(buckets, period),
        windowEnd: now,
      ),
    ]);
  }

  /// The page shell, identical whether or not the data has landed.
  Widget _page(BuildContext context, List<Widget> children) => Scaffold(
    appBar: AppBar(title: Text(context.l10n.statsTitle)),
    // Deliberately not a ListView: its sliver delegate disposes children
    // scrolled past the cache extent, and neither TweenAnimationBuilder nor
    // fl_chart keeps itself alive. Once the chart slots below are filled,
    // scrolling the hero row off-screen and back would remount the tiles and
    // replay the count-up, against the spec's "once per screen open". The
    // page is a small fixed set of children, so building them all is cheaper
    // than keep-alive plumbing on every entrance animation.
    body: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        // Matches the tight cross-axis constraints ListView handed down.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
}

/// Shows one heatmap day's exact figures.
///
/// Reports what that day held and nothing else — no comparison to other days,
/// no note about an empty one.
void _showDayDetail(BuildContext context, HeatmapDay day) {
  final l10n = context.l10n;
  final locale = Localizations.localeOf(context).toLanguageTag();
  final counts = NumberFormat.decimalPattern(locale);

  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat.yMMMMd(locale).format(day.day),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            // The heatmap stores whole minutes, so this reads the same "0m"
            // the aggregator floored a short session down to.
            _detailRow(
              context,
              l10n.statsHeroReadingTime,
              formatDuration(
                l10n,
                day.minutes * Duration.millisecondsPerMinute,
              ),
            ),
            _detailRow(
              context,
              l10n.statsHeroCharactersRead,
              counts.format(day.charactersRead),
            ),
            _detailRow(
              context,
              l10n.statsHeatmapLookups,
              counts.format(day.lookups),
            ),
          ],
        ),
      ),
    ),
  );
}

/// One label/value line of the day detail sheet.
Widget _detailRow(BuildContext context, String label, String value) {
  final theme = Theme.of(context);
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: theme.textTheme.bodyMedium),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

/// The three headline figures for the current period and format selection.
class _HeroStatsRow extends StatelessWidget {
  const _HeroStatsRow({required this.totals});

  final PeriodTotals totals;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final counts = NumberFormat.decimalPattern(
      Localizations.localeOf(context).toLanguageTag(),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heroTile(
            label: l10n.statsHeroReadingTime,
            value: totals.durationMs,
            formatter: (ms) => formatDuration(l10n, ms),
          ),
          _heroTile(
            label: l10n.statsHeroCharactersRead,
            value: totals.charactersRead,
            formatter: counts.format,
          ),
          _heroTile(
            label: l10n.statsHeroWordsAdded,
            value: totals.wordsAdded,
            formatter: counts.format,
          ),
        ],
      ),
    );
  }

  /// One third of the row. The tile scales its own number down to fit.
  Widget _heroTile({
    required String label,
    required int value,
    required String Function(int) formatter,
  }) {
    return Expanded(
      child: HeroStatTile(label: label, value: value, formatter: formatter),
    );
  }
}

/// Format filter and period selector, in one row per the spec.
class _ControlRow extends ConsumerWidget {
  const _ControlRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final format = ref.watch(selectedStatsFormatProvider);
    final period = ref.watch(selectedStatsPeriodProvider);

    // Seven segments do not fit a phone width, and the spec asks for one row —
    // so the row scrolls rather than wrapping into a second one.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          SegmentedButton<StatsFormat>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: StatsFormat.all,
                label: Text(l10n.statsFormatAll),
              ),
              ButtonSegment(
                value: StatsFormat.epub,
                label: Text(l10n.statsFormatEpub),
              ),
              ButtonSegment(
                value: StatsFormat.manga,
                label: Text(l10n.statsFormatManga),
              ),
            ],
            selected: {format},
            onSelectionChanged: (selection) =>
                ref.read(selectedStatsFormatProvider.notifier).state =
                    selection.first,
          ),
          const SizedBox(width: 12),
          SegmentedButton<StatsPeriod>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: StatsPeriod.week,
                label: Text(l10n.statsPeriodWeek),
              ),
              ButtonSegment(
                value: StatsPeriod.month,
                label: Text(l10n.statsPeriodMonth),
              ),
              ButtonSegment(
                value: StatsPeriod.year,
                label: Text(l10n.statsPeriodYear),
              ),
              ButtonSegment(
                value: StatsPeriod.all,
                label: Text(l10n.statsPeriodAll),
              ),
            ],
            selected: {period},
            onSelectionChanged: (selection) =>
                ref.read(selectedStatsPeriodProvider.notifier).state =
                    selection.first,
          ),
        ],
      ),
    );
  }
}
