import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/free_books/data/catalog_counts.dart';
import 'package:mekuru/features/free_books/presentation/screens/free_books_screen.dart';
import 'package:mekuru/features/settings/presentation/screens/settings_screen.dart';
import 'package:mekuru/features/stats/data/services/stats_aggregator.dart';
import 'package:mekuru/features/stats/presentation/providers/stats_providers.dart';
import 'package:mekuru/features/stats/presentation/screens/stats_screen.dart';
import 'package:mekuru/features/stats/presentation/stats_formatting.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/utils/app_routes.dart';
import 'package:mekuru/shared/utils/haptics.dart';

/// The You tab: a hub of large cards for Free books, Reading stats and
/// Settings.
class YouScreen extends ConsumerWidget {
  const YouScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final sessions = ref.watch(sessionsProvider).value;
    final weekMs = sessions == null
        ? null
        : periodTotals(
            sessions: sessions,
            events: const [],
            period: StatsPeriod.week,
            now: DateTime.now(),
          ).durationMs;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navYou)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _HubCard(
            icon: Icons.local_library_outlined,
            title: l10n.freeBooksTitle,
            subtitle: l10n.youFreeBooksSubtitle(
              count: aozoraWorkCount ~/ 1000 * 1000,
            ),
            onTap: () => Navigator.of(
              context,
            ).push(namedRoute('free_books', (_) => const FreeBooksScreen())),
          ),
          _HubCard(
            icon: Icons.insights_outlined,
            title: l10n.statsScreenTitle,
            subtitle: l10n.youStatsSubtitle(
              duration: formatDuration(l10n, weekMs ?? 0),
            ),
            onTap: () => Navigator.of(
              context,
            ).push(namedRoute('stats', (_) => const StatsScreen())),
          ),
          _HubCard(
            icon: Icons.settings_outlined,
            title: l10n.settingsTitle,
            subtitle: l10n.youSettingsSubtitle,
            onTap: () => Navigator.of(
              context,
            ).push(namedRoute('settings', (_) => const SettingsScreen())),
          ),
        ],
      ),
    );
  }
}

class _HubCard extends StatelessWidget {
  const _HubCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 12,
        ),
        leading: Icon(icon, size: 32, color: theme.colorScheme.primary),
        title: Text(title, style: theme.textTheme.titleMedium),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          AppHaptics.light();
          onTap();
        },
      ),
    );
  }
}
