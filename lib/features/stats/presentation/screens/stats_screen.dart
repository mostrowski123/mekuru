import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/stats/data/services/stats_aggregator.dart';
import 'package:mekuru/features/stats/presentation/providers/stats_providers.dart';
import 'package:mekuru/features/stats/presentation/widgets/hero_stat_tile.dart';
import 'package:mekuru/l10n/l10n.dart';

/// Formats a duration in milliseconds the way the stats surfaces show it:
/// `"0m"`, `"42m"`, `"3h 20m"`.
///
/// Shared with the Library summary strip, so the two never disagree. Hours are
/// never rolled up into days — an all-time total reads `"30h 5m"`, which is the
/// figure people expect on a reading tile. Whole hours keep the minute part
/// (`"2h 0m"`) so the string does not change shape mid count-up. Negative input
/// (a clock change that slipped past the aggregator's clamping) reads `"0m"`
/// rather than a minus sign.
String formatDuration(int ms) {
  final totalMinutes = (ms < 0 ? 0 : ms) ~/ Duration.millisecondsPerMinute;
  final hours = totalMinutes ~/ Duration.minutesPerHour;
  final minutes = totalMinutes % Duration.minutesPerHour;
  return hours == 0 ? '${minutes}m' : '${hours}h ${minutes}m';
}

/// Reading statistics: headline numbers first, then the filters, then the
/// chart cards.
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.statsTitle)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
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
    );
  }

  /// PLACEHOLDER (Task 10): year activity heatmap.
  Widget _buildHeatmapCard(BuildContext context, WidgetRef ref) =>
      const SizedBox.shrink();

  /// PLACEHOLDER (Task 11): reading time per bucket, EPUB vs manga.
  Widget _buildReadingTimeCard(BuildContext context, WidgetRef ref) =>
      const SizedBox.shrink();

  /// PLACEHOLDER (Task 11): characters read per bucket, pages as a figure.
  Widget _buildVolumeCard(BuildContext context, WidgetRef ref) =>
      const SizedBox.shrink();

  /// PLACEHOLDER (Task 11): lookups per 1,000 characters, as a trend line.
  Widget _buildLookupRateCard(BuildContext context, WidgetRef ref) =>
      const SizedBox.shrink();

  /// PLACEHOLDER (Task 11): cumulative unique expressions over time.
  Widget _buildVocabGrowthCard(BuildContext context, WidgetRef ref) =>
      const SizedBox.shrink();
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

  /// One third of the row. [FittedBox] scales the tile down rather than
  /// clipping it: a six-figure character count in a headline face does not fit
  /// a third of a phone screen, and the number is the point of the tile.
  Widget _heroTile({
    required String label,
    required int value,
    required String Function(int) formatter,
  }) {
    return Expanded(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: HeroStatTile(label: label, value: value, formatter: formatter),
      ),
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
