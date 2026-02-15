import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_importer.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_query_service.dart';
import 'package:mekuru/main.dart';

// ──────────────── Repository & Services ────────────────

/// Provider for the dictionary repository.
final dictionaryRepositoryProvider = Provider<DictionaryRepository>((ref) {
  return DictionaryRepository(ref.watch(databaseProvider));
});

/// Provider for the dictionary query service.
final dictionaryQueryServiceProvider = Provider<DictionaryQueryService>((ref) {
  return DictionaryQueryService(ref.watch(databaseProvider));
});

/// Provider for the dictionary importer.
final dictionaryImporterProvider = Provider<DictionaryImporter>((ref) {
  return DictionaryImporter(ref.watch(dictionaryRepositoryProvider));
});

// ──────────────── Data Providers ────────────────

/// Reactive stream of all dictionaries.
final dictionariesProvider = StreamProvider<List<DictionaryMeta>>((ref) {
  return ref.watch(dictionaryRepositoryProvider).watchAllDictionaries();
});

// ──────────────── Import State ────────────────

/// State for dictionary import progress.
class DictionaryImportState {
  final bool isImporting;
  final int processedEntries;
  final int totalEntries;
  final String? error;
  final String? successMessage;

  const DictionaryImportState({
    this.isImporting = false,
    this.processedEntries = 0,
    this.totalEntries = 0,
    this.error,
    this.successMessage,
  });

  double get progress => totalEntries > 0 ? processedEntries / totalEntries : 0;

  DictionaryImportState copyWith({
    bool? isImporting,
    int? processedEntries,
    int? totalEntries,
    String? error,
    String? successMessage,
  }) {
    return DictionaryImportState(
      isImporting: isImporting ?? this.isImporting,
      processedEntries: processedEntries ?? this.processedEntries,
      totalEntries: totalEntries ?? this.totalEntries,
      error: error,
      successMessage: successMessage,
    );
  }
}

/// Notifier for managing dictionary import state.
class DictionaryImportNotifier extends Notifier<DictionaryImportState> {
  @override
  DictionaryImportState build() => const DictionaryImportState();

  /// Import a dictionary from a file path.
  Future<void> importDictionary(String filePath) async {
    state = const DictionaryImportState(isImporting: true);

    try {
      final importer = ref.read(dictionaryImporterProvider);
      final count = await importer.importFromFile(
        filePath,
        onProgress: (processed, total) {
          state = state.copyWith(
            processedEntries: processed,
            totalEntries: total,
          );
        },
      );
      state = DictionaryImportState(
        successMessage: 'Imported $count entries successfully!',
      );
    } catch (e) {
      state = DictionaryImportState(error: e.toString());
    }
  }
}

final dictionaryImportProvider =
    NotifierProvider<DictionaryImportNotifier, DictionaryImportState>(
      DictionaryImportNotifier.new,
    );
