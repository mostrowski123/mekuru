import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/stats/data/services/stats_aggregator.dart';
import 'package:mekuru/features/stats/presentation/providers/stats_providers.dart';
import 'package:mekuru/features/stats/presentation/screens/stats_screen.dart';
import 'package:mekuru/features/stats/presentation/stats_formatting.dart';
import 'package:mekuru/l10n/l10n.dart';

/// The trailing week's reading, as a compact tappable strip above the library
/// grid, opening the stats screen.
///
/// A miniature of the stats design language rather than a chart: the accent
/// carries the identity (the icon), the figures are ink-colored text at the
/// body scale, and nothing animates — the library is not a reward surface.
class LibraryStatsStrip extends ConsumerWidget {
  const LibraryStatsStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionsProvider).value;
    // Three cases collapse into one blank: nothing read yet (the spec's "no
    // zero-state noise on first launch"), the stream still in flight, and the
    // stream having failed. The library must never be blocked or made noisy
    // by the stats database.
    if (sessions == null || sessions.isEmpty) return const SizedBox.shrink();

    // Combined totals on purpose: the stats screen's format filter is that
    // screen's own state, and a strip that silently showed only manga would
    // misreport the week. No word events either — the strip has no room for a
    // third figure, so `wordsAdded` is left at zero rather than computed.
    final totals = periodTotals(
      sessions: sessions,
      events: const [],
      period: StatsPeriod.week,
      now: DateTime.now(),
    );

    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Padding(
      // Matches the continue-reading card directly below it.
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openStats(context),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  Icons.insights,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.statsStripThisWeek,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        // The dot is chrome between two independently
                        // localized figures, not translatable copy.
                        '${formatDuration(l10n, totals.durationMs)} · '
                        '${l10n.statsStripCharacters(count: totals.charactersRead)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openStats(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const StatsScreen()));
  }
}
