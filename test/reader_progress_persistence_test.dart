import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/reader/data/services/reader_progress_persistence.dart';

void main() {
  group('ReaderProgressPersistence', () {
    test(
      'debounces rapid progress updates and saves only the latest CFI',
      () async {
        final savedCfis = <String>[];
        final persistence = ReaderProgressPersistence(
          debounceDuration: const Duration(milliseconds: 60),
          saveProgress: (cfi) async {
            savedCfis.add(cfi);
          },
        );

        persistence.queueSave('cfi-1');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        persistence.queueSave('cfi-2');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        persistence.queueSave('cfi-3');
        await Future<void>.delayed(const Duration(milliseconds: 80));

        expect(savedCfis, ['cfi-3']);
        await persistence.dispose();
      },
    );

    test('does not save duplicate CFIs repeatedly', () async {
      final savedCfis = <String>[];
      final persistence = ReaderProgressPersistence(
        debounceDuration: const Duration(milliseconds: 40),
        saveProgress: (cfi) async {
          savedCfis.add(cfi);
        },
      );

      persistence.queueSave('same-cfi');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(savedCfis, ['same-cfi']);

      persistence.queueSave('same-cfi');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(savedCfis, ['same-cfi']);
      await persistence.dispose();
    });
  });
}
