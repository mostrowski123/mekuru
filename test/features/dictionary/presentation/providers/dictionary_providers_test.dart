import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';

void main() {
  group('DictionaryImportState.copyWith', () {
    test('preserves existing error when copyWith does not pass one', () {
      const seeded = DictionaryImportState(error: 'boom');

      final next = seeded.copyWith(currentDictionary: 'Parsing collection...');

      expect(next.error, 'boom');
      expect(next.currentDictionary, 'Parsing collection...');
    });

    test(
      'preserves existing successMessage when copyWith does not pass one',
      () {
        const seeded = DictionaryImportState(successMessage: 'done!');

        final next = seeded.copyWith(processedEntries: 5, totalEntries: 10);

        expect(next.successMessage, 'done!');
        expect(next.processedEntries, 5);
        expect(next.totalEntries, 10);
      },
    );

    test('keeps all other fields when only one is updated', () {
      const seeded = DictionaryImportState(
        isImporting: true,
        processedEntries: 1,
        totalEntries: 2,
        currentDictionary: 'A',
        dictionariesProcessed: 0,
        dictionariesTotal: 3,
        error: 'err',
        successMessage: 'ok',
      );

      final next = seeded.copyWith(processedEntries: 99);

      expect(next.isImporting, true);
      expect(next.processedEntries, 99);
      expect(next.totalEntries, 2);
      expect(next.currentDictionary, 'A');
      expect(next.dictionariesProcessed, 0);
      expect(next.dictionariesTotal, 3);
      expect(next.error, 'err');
      expect(next.successMessage, 'ok');
    });

    test('copyWith on a clean state leaves error/successMessage null', () {
      const seeded = DictionaryImportState();

      final next = seeded.copyWith(isImporting: true);

      expect(next.error, isNull);
      expect(next.successMessage, isNull);
      expect(next.isImporting, true);
    });
  });
}
