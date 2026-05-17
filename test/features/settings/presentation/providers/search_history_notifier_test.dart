import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SearchHistoryNotifier', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('addSearch on empty state stores the term', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(searchHistoryProvider.notifier).addSearch('食べる');

      expect(container.read(searchHistoryProvider), ['食べる']);
    });

    test('addSearch deduplicates and promotes the term to the head', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(searchHistoryProvider.notifier);
      notifier.addSearch('食べる');
      notifier.addSearch('走る');
      notifier.addSearch('食べる');

      expect(container.read(searchHistoryProvider), ['食べる', '走る']);
    });

    test('addSearch is a no-op when the term is already at the head', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(searchHistoryProvider.notifier);
      notifier.addSearch('食べる');
      final stateBefore = container.read(searchHistoryProvider);

      notifier.addSearch('食べる');
      final stateAfter = container.read(searchHistoryProvider);

      // The MRU short-circuit must skip the list rebuild AND the persistence
      // write — observable here as the same list reference surviving.
      expect(identical(stateBefore, stateAfter), isTrue);
      expect(stateAfter, ['食べる']);
    });

    test('addSearch ignores empty and whitespace-only terms', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(searchHistoryProvider.notifier);
      notifier.addSearch('');
      notifier.addSearch('   ');

      expect(container.read(searchHistoryProvider), isEmpty);
    });

    test('addSearch caps history at maxEntries', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(searchHistoryProvider.notifier);
      for (var i = 0; i < SearchHistoryNotifier.maxEntries + 5; i++) {
        notifier.addSearch('term$i');
      }

      final history = container.read(searchHistoryProvider);
      expect(history.length, SearchHistoryNotifier.maxEntries);
      expect(history.first, 'term${SearchHistoryNotifier.maxEntries + 4}');
    });

    test('removeSearch deletes a specific term', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(searchHistoryProvider.notifier);
      notifier.addSearch('食べる');
      notifier.addSearch('走る');
      notifier.removeSearch('食べる');

      expect(container.read(searchHistoryProvider), ['走る']);
    });

    test('clearAll empties the history', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(searchHistoryProvider.notifier);
      notifier.addSearch('食べる');
      notifier.addSearch('走る');
      notifier.clearAll();

      expect(container.read(searchHistoryProvider), isEmpty);
    });
  });
}
