import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/platform/file_pick.dart';
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
/// Opens a save-file dialog so the user can choose where to save the CSV.
final exportVocabularyProvider =
    Provider.autoDispose<
      Future<FileDialogResult<void>> Function({Set<int>? selectedIds})
    >((ref) {
      return ({Set<int>? selectedIds}) async {
        final repo = ref.read(vocabularyRepositoryProvider);
        final file = await repo.exportToCsv(selectedIds: selectedIds);
        return saveFile(file.path, mimeType: 'text/csv');
      };
    });
