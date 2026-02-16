import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/reader/data/services/reader_progress_persistence.dart';

void main() {
  group('ReaderProgressPersistence', () {
    test(
      'debounces rapid progress updates and saves only the latest CFI',
      () async {
        final savedEntries = <(String, double)>[];
        final persistence = ReaderProgressPersistence(
          debounceDuration: const Duration(milliseconds: 60),
          saveProgress: (cfi, progress) async {
            savedEntries.add((cfi, progress));
          },
        );

        persistence.queueSave('cfi-1', 0.1);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        persistence.queueSave('cfi-2', 0.2);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        persistence.queueSave('cfi-3', 0.3);
        await Future<void>.delayed(const Duration(milliseconds: 80));

        expect(savedEntries, [('cfi-3', 0.3)]);
        await persistence.dispose();
      },
    );

    test('does not save duplicate CFIs repeatedly', () async {
      final savedEntries = <(String, double)>[];
      final persistence = ReaderProgressPersistence(
        debounceDuration: const Duration(milliseconds: 40),
        saveProgress: (cfi, progress) async {
          savedEntries.add((cfi, progress));
        },
      );

      persistence.queueSave('same-cfi', 0.5);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(savedEntries, [('same-cfi', 0.5)]);

      persistence.queueSave('same-cfi', 0.5);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(savedEntries, [('same-cfi', 0.5)]);
      await persistence.dispose();
    });
  });
}
