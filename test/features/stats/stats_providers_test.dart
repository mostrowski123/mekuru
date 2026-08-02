import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/stats/data/services/stats_aggregator.dart';
import 'package:mekuru/features/stats/presentation/providers/stats_providers.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });
  tearDown(() => container.dispose());

  test('period selection resets to the trailing week when the screen '
      'stops listening', () async {
    var sub = container.listen(selectedStatsPeriodProvider, (_, _) {});
    container.read(selectedStatsPeriodProvider.notifier).state =
        StatsPeriod.year;
    expect(container.read(selectedStatsPeriodProvider), StatsPeriod.year);

    sub.close();
    await container.pump();

    sub = container.listen(selectedStatsPeriodProvider, (_, _) {});
    expect(container.read(selectedStatsPeriodProvider), StatsPeriod.week);
    sub.close();
  });

  test('format selection resets to all formats when the screen '
      'stops listening', () async {
    var sub = container.listen(selectedStatsFormatProvider, (_, _) {});
    container.read(selectedStatsFormatProvider.notifier).state =
        StatsFormat.manga;
    expect(container.read(selectedStatsFormatProvider), StatsFormat.manga);

    sub.close();
    await container.pump();

    sub = container.listen(selectedStatsFormatProvider, (_, _) {});
    expect(container.read(selectedStatsFormatProvider), StatsFormat.all);
    sub.close();
  });

  test('selection is kept while the screen is still listening', () async {
    final sub = container.listen(selectedStatsPeriodProvider, (_, _) {});
    container.read(selectedStatsPeriodProvider.notifier).state =
        StatsPeriod.month;

    await container.pump();

    expect(container.read(selectedStatsPeriodProvider), StatsPeriod.month);
    sub.close();
  });
}
