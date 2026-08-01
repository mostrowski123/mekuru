import 'package:flutter_riverpod/flutter_riverpod.dart';
// StateProvider is not exported from flutter_riverpod.dart in Riverpod 3 — it
// lives in the legacy barrel. It is still supported (marked `@publicInLegacy`,
// not deprecated) and is the right shape for two plain UI-local enum toggles.
import 'package:flutter_riverpod/legacy.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/stats/data/repositories/stats_repository.dart';
import 'package:mekuru/features/stats/data/services/stats_aggregator.dart';
import 'package:mekuru/main.dart';

/// Provider for StatsRepository.
final statsRepositoryProvider = Provider<StatsRepository>((ref) {
  return StatsRepository(ref.watch(databaseProvider));
});

/// The window the stats screen is currently showing.
///
/// Screen-local UI state, deliberately not persisted: the stats screen is a
/// weekly-glance surface, so every visit should open on the trailing week.
final selectedStatsPeriodProvider = StateProvider<StatsPeriod>(
  (ref) => StatsPeriod.week,
);

/// The book format every chart on the stats screen is restricted to.
final selectedStatsFormatProvider = StateProvider<StatsFormat>(
  (ref) => StatsFormat.all,
);

/// Every recorded session, oldest first.
///
/// The whole table is watched and aggregated in memory on purpose — rows are
/// added a handful of times a day, and the charts each need a different slice
/// of the same set, so one stream beats several windowed queries.
final sessionsProvider = StreamProvider<List<ReadingSession>>(
  (ref) => ref.watch(statsRepositoryProvider).watchAllSessions(),
);

/// Every recorded vocabulary event, oldest first.
final wordEventsProvider = StreamProvider<List<WordEvent>>(
  (ref) => ref.watch(statsRepositoryProvider).watchAllWordEvents(),
);
