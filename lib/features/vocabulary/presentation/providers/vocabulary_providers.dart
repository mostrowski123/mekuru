import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/vocabulary/data/repositories/vocabulary_repository.dart';
import 'package:mekuru/main.dart';

/// Provider for VocabularyRepository.
final vocabularyRepositoryProvider = Provider<VocabularyRepository>((ref) {
  return VocabularyRepository(ref.watch(databaseProvider));
});

/// Stream of all saved words.
final vocabularyListProvider = StreamProvider<List<SavedWord>>((ref) {
  return ref.watch(vocabularyRepositoryProvider).watchAllWords();
});

/// Export vocabulary function.
/// Accepts an optional [selectedIds] set to export only specific words.
/// Opens a save-file dialog so the user can choose where to save the CSV,
/// and returns where it was saved, or null when the user cancelled.
final exportVocabularyProvider =
    Provider.autoDispose<Future<String?> Function({Set<int>? selectedIds})>((
      ref,
    ) {
      return ({Set<int>? selectedIds}) async {
        final repo = ref.read(vocabularyRepositoryProvider);
        final file = await repo.exportToCsv(selectedIds: selectedIds);

        final date = DateTime.now().toIso8601String().split('T').first;

        // No dialogTitle or type filter: Android's and iOS's save dialogs
        // ignore both; the .csv name is what matters.
        return FilePicker.saveFile(
          fileName: 'vocabulary_export_$date.csv',
          bytes: await file.readAsBytes(),
        );
      };
    });
