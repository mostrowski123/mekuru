import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/vocabulary/data/repositories/vocabulary_repository.dart';
import 'package:mekuru/main.dart';
import 'package:share_plus/share_plus.dart';

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
final exportVocabularyProvider = Provider.autoDispose<Future<void> Function({Set<int>? selectedIds})>((
  ref,
) {
  return ({Set<int>? selectedIds}) async {
    final repo = ref.read(vocabularyRepositoryProvider);
    final xFile = await repo.exportToCsv(selectedIds: selectedIds);

    // Share the file
    // ignore: deprecated_member_use
    await Share.shareXFiles([xFile], subject: 'My Japanese Vocabulary');
  };
});
