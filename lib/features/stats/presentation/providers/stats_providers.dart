import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/stats/data/repositories/stats_repository.dart';
import 'package:mekuru/main.dart';

/// Provider for StatsRepository.
final statsRepositoryProvider = Provider<StatsRepository>((ref) {
  return StatsRepository(ref.watch(databaseProvider));
});
