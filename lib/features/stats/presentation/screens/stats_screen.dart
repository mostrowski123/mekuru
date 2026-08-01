import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mekuru/core/database/database_provider.dart';
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
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
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
          children: [
            // Hero numbers come before any chart: the spec's reward surface
            // leads with typography, not with axes.
            const _HeroStatsRow(),
            const SizedBox(height: 20),
            const _ControlRow(),
            const SizedBox(height: 8),
            // Chart cards land below, in spec order. Each slot is a separate
            // builder so the chart tasks have an unambiguous insertion point.
            _buildHeatmapCard(context, ref),
            _buildReadingTimeCard(context, ref),
            _buildVolumeCard(context, ref),
            _buildLookupRateCard(context, ref),
            _buildVocabGrowthCard(context, ref),
          ],
        ),
      ),
    );
  }

  /// The trailing year of activity, one cell per day.
  ///
  /// Deliberately reads the format filter but not the period selector: the
  /// heatmap is the year view, and shrinking it to the selected window would
  /// leave the screen with two competing time axes.
  Widget _buildHeatmapCard(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionsProvider).value;
    if (sessions == null) return const SizedBox.shrink();

    final format = ref.watch(selectedStatsFormatProvider);
    return ActivityHeatmapCard(
      days: heatmapDays(filterSessions(sessions, format), DateTime.now()),
      onDayTap: (day) => _showDayDetail(context, day),
    );
  }

  /// Time read per bucket, EPUB and manga stacked apart in the All view.
  ///
  /// Each format is bucketed on its own grid so the card can color the two
  /// apart; the filter drops a series by handing the card nothing for it.
  Widget _buildReadingTimeCard(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionsProvider).value;
    if (sessions == null) return const SizedBox.shrink();

    final format = ref.watch(selectedStatsFormatProvider);
    final period = ref.watch(selectedStatsPeriodProvider);
    final now = DateTime.now();
    return ReadingTimeCard(
      epubBuckets: format == StatsFormat.manga
          ? const []
          : bucketize(filterSessions(sessions, StatsFormat.epub), period, now),
      mangaBuckets: format == StatsFormat.epub
          ? const []
          : bucketize(filterSessions(sessions, StatsFormat.manga), period, now),
      period: period,
      // All-time, not window-limited: the card only annotates it when the day
      // happens to fall inside the window on screen.
      bestDay: bestDay(filterSessions(sessions, format), now),
    );
  }

  /// Characters read per bucket, with the period's pages as a header figure.
  Widget _buildVolumeCard(BuildContext context, WidgetRef ref) {
    final buckets = _selectedBuckets(ref);
    if (buckets == null) return const SizedBox.shrink();
    return VolumeCard(
      buckets: buckets,
      period: ref.watch(selectedStatsPeriodProvider),
    );
  }

  /// Lookups per 1,000 characters, as a trend line with gaps.
  Widget _buildLookupRateCard(BuildContext context, WidgetRef ref) {
    final buckets = _selectedBuckets(ref);
    if (buckets == null) return const SizedBox.shrink();
    return LookupRateCard(
      buckets: buckets,
      period: ref.watch(selectedStatsPeriodProvider),
    );
  }

  /// Cumulative distinct expressions over the selected window.
  Widget _buildVocabGrowthCard(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionsProvider).value;
    final events = ref.watch(wordEventsProvider).value;
    if (sessions == null || events == null) return const SizedBox.shrink();

    final format = ref.watch(selectedStatsFormatProvider);
    final period = ref.watch(selectedStatsPeriodProvider);
    final now = DateTime.now();
    return VocabGrowthCard(
      points: cumulativeUniqueWords(filterWordEvents(events, format)),
      // Read off the same bucket grid the other cards use, so the curve and
      // the bars cover the same days.
      windowStart: _windowStart(
        bucketize(filterSessions(sessions, format), period, now),
        period,
      ),
      windowEnd: now,
    );
  }

  /// The buckets the period and format selectors currently ask for, or null
  /// while the sessions stream is still in flight.
  List<StatBucket>? _selectedBuckets(WidgetRef ref) {
    final sessions = ref.watch(sessionsProvider).value;
    if (sessions == null) return null;
    return bucketize(
      filterSessions(sessions, ref.watch(selectedStatsFormatProvider)),
      ref.watch(selectedStatsPeriodProvider),
      DateTime.now(),
    );
  }
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
              formatDuration(day.minutes * Duration.millisecondsPerMinute),
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
class _HeroStatsRow extends ConsumerWidget {
  const _HeroStatsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final sessions = ref.watch(sessionsProvider);
    final events = ref.watch(wordEventsProvider);

    final sessionRows = sessions.value;
    final eventRows = events.value;
    if (sessionRows == null || eventRows == null) {
      // Nothing is rendered until both streams land, so the count-up runs once
      // with the real numbers instead of animating to zero and then cutting.
      if (!sessions.hasError && !events.hasError) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          l10n.statsUnavailable,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    final format = ref.watch(selectedStatsFormatProvider);
    final period = ref.watch(selectedStatsPeriodProvider);
    final totals = _periodTotals(
      sessions: filterSessions(sessionRows, format),
      events: filterWordEvents(eventRows, format),
      period: period,
      now: DateTime.now(),
    );

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
            formatter: formatDuration,
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

/// The numbers behind the three hero tiles.
class _PeriodTotals {
  const _PeriodTotals({
    required this.durationMs,
    required this.charactersRead,
    required this.wordsAdded,
  });

  final int durationMs;
  final int charactersRead;
  final int wordsAdded;
}

_PeriodTotals _periodTotals({
  required List<ReadingSession> sessions,
  required List<WordEvent> events,
  required StatsPeriod period,
  required DateTime now,
}) {
  final buckets = bucketize(sessions, period, now);
  var durationMs = 0;
  var charactersRead = 0;
  for (final bucket in buckets) {
    durationMs += bucket.durationMs;
    charactersRead += bucket.charactersRead;
  }
  return _PeriodTotals(
    durationMs: durationMs,
    charactersRead: charactersRead,
    wordsAdded: _wordsAddedSince(events, _windowStart(buckets, period)),
  );
}

/// The first instant [period] covers, or null when it has no lower bound.
///
/// Read off the bucket grid rather than recomputed, so the tiles can never
/// drift out of step with the aggregator's trailing-window arithmetic.
/// [StatsPeriod.all] is the exception: its grid starts at the first *session*'s
/// month, which would drop words saved outside a reader before any session
/// existed — including every row the migration backfilled.
DateTime? _windowStart(List<StatBucket> buckets, StatsPeriod period) {
  if (period == StatsPeriod.all || buckets.isEmpty) return null;
  return buckets.first.start;
}

/// Distinct expressions first seen on or after [start] — all of them when
/// [start] is null.
///
/// Derived from the cumulative curve rather than counted directly, so this tile
/// and the vocab-growth chart agree to the word: both credit an expression once,
/// on the day of its first event, whatever the event's kind.
int _wordsAddedSince(List<WordEvent> events, DateTime? start) {
  final points = cumulativeUniqueWords(events);
  if (points.isEmpty) return 0;

  final total = points.last.total;
  if (start == null) return total;

  // Points ascend chronologically, so the last one before the window carries
  // the running total the window started from.
  var before = 0;
  for (final point in points) {
    if (!point.day.isBefore(start)) break;
    before = point.total;
  }
  return total - before;
}
