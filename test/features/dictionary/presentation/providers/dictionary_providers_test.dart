import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';

void main() {
  group('DictionaryImportState.copyWith', () {
    test('keeps the last failure', () {
      final seeded = DictionaryImportState(failure: StateError('boom'));

      final next = seeded.copyWith(
        step: DictionaryImportStep.parsingCollection,
      );

      expect(next.failure, isA<StateError>());
      expect(next.step, DictionaryImportStep.parsingCollection);
    });

    test('keeps what the last import added', () {
      const seeded = DictionaryImportState(
        imported: (entries: 3, dictionaries: null),
      );

      final next = seeded.copyWith(processedEntries: 5, totalEntries: 10);

      expect(next.imported, (entries: 3, dictionaries: null));
      expect(next.processedEntries, 5);
      expect(next.totalEntries, 10);
    });

    test('keeps all other fields when only one is updated', () {
      const seeded = DictionaryImportState(
        isImporting: true,
        processedEntries: 1,
        totalEntries: 2,
        currentDictionary: 'A',
        step: DictionaryImportStep.finishing,
        dictionariesProcessed: 0,
        dictionariesTotal: 3,
        failure: 'err',
        imported: (entries: 1, dictionaries: 1),
      );

      final next = seeded.copyWith(processedEntries: 99);

      expect(next.isImporting, true);
      expect(next.processedEntries, 99);
      expect(next.totalEntries, 2);
      expect(next.currentDictionary, 'A');
      expect(next.step, DictionaryImportStep.finishing);
      expect(next.dictionariesProcessed, 0);
      expect(next.dictionariesTotal, 3);
      expect(next.failure, 'err');
      expect(next.imported, (entries: 1, dictionaries: 1));
    });

    test('copyWith on a clean state leaves failure and imported null', () {
      const seeded = DictionaryImportState();

      final next = seeded.copyWith(isImporting: true);

      expect(next.failure, isNull);
      expect(next.imported, isNull);
      expect(next.isImporting, true);
    });
  });
}
