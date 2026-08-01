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
    final sessionsAsync = ref.watch(sessionsProvider);
    // The stream still in flight and the stream having failed both collapse
    // into one blank: the library must never be blocked or made noisy by the
    // stats database. Having *no sessions yet* is not one of those cases —
    // the strip is the only route to the stats screen, so it stays visible
    // from first launch (post-QA user decision, 2026-08-02).
    if (sessionsAsync.hasError) return const SizedBox.shrink();
    final sessions = sessionsAsync.value;
    if (sessions == null) return const SizedBox.shrink();

    // Combined totals on purpose: the stats screen's format filter is that
    // screen's own state, and a strip that silently showed only manga would
    // misreport the week. No word events either — the strip has no room for a
    // third figure, so `wordsAdded` is left at zero rather than computed.
    final totals = sessions.isEmpty
        ? null
        : periodTotals(
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
                  // Before anything has been read there is no week to name and
                  // no figure worth printing, so the strip carries a single
                  // neutral line naming its destination — not a row of zeros,
                  // and not a nudge to start reading.
                  child: totals == null
                      ? Text(
                          l10n.statsStripEmpty,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      : Column(
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
