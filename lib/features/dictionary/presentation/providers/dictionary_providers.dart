import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_importer.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_query_service.dart';
import 'package:mekuru/main.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

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
  final String? currentDictionary;
  final int dictionariesProcessed;
  final int dictionariesTotal;
  final List<String> skippedDictionaries;
  final String? error;
  final String? successMessage;

  const DictionaryImportState({
    this.isImporting = false,
    this.processedEntries = 0,
    this.totalEntries = 0,
    this.currentDictionary,
    this.dictionariesProcessed = 0,
    this.dictionariesTotal = 0,
    this.skippedDictionaries = const [],
    this.error,
    this.successMessage,
  });

  double get progress => totalEntries > 0 ? processedEntries / totalEntries : 0;

  DictionaryImportState copyWith({
    bool? isImporting,
    int? processedEntries,
    int? totalEntries,
    String? currentDictionary,
    int? dictionariesProcessed,
    int? dictionariesTotal,
    List<String>? skippedDictionaries,
    String? error,
    String? successMessage,
  }) {
    return DictionaryImportState(
      isImporting: isImporting ?? this.isImporting,
      processedEntries: processedEntries ?? this.processedEntries,
      totalEntries: totalEntries ?? this.totalEntries,
      currentDictionary: currentDictionary ?? this.currentDictionary,
      dictionariesProcessed:
          dictionariesProcessed ?? this.dictionariesProcessed,
      dictionariesTotal: dictionariesTotal ?? this.dictionariesTotal,
      skippedDictionaries: skippedDictionaries ?? this.skippedDictionaries,
      error: error,
      successMessage: successMessage,
    );
  }
}

/// Notifier for managing dictionary import state.
class DictionaryImportNotifier extends Notifier<DictionaryImportState> {
  @override
  DictionaryImportState build() => const DictionaryImportState();

  /// Import a dictionary file. Detects format by extension:
  /// - `.zip` → single Yomitan dictionary
  /// - `.json` → Dexie collection export (multiple dictionaries)
  Future<void> importDictionary(String filePath) async {
    if (filePath.endsWith('.json')) {
      await _importCollection(filePath);
    } else {
      await _importSingleZip(filePath);
    }
  }

  Future<void> _importSingleZip(String filePath) async {
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
      Sentry.addBreadcrumb(Breadcrumb(
        message: 'Dictionary imported ($count entries)',
        category: 'dictionary',
      ));
      state = DictionaryImportState(
        successMessage: 'Imported $count entries successfully!',
      );
    } catch (e) {
      state = DictionaryImportState(error: e.toString());
    }
  }

  Future<void> _importCollection(String filePath) async {
    state = const DictionaryImportState(isImporting: true);
    final skipped = <String>[];

    try {
      final importer = ref.read(dictionaryImporterProvider);
      final result = await importer.importCollectionFromFile(
        filePath,
        onParsing: () {
          state = state.copyWith(
            currentDictionary: 'Parsing collection...',
          );
        },
        onDictionaryStart: (name, entryCount, dictIndex, dictTotal) {
          state = state.copyWith(
            currentDictionary: name,
            processedEntries: 0,
            totalEntries: entryCount,
            dictionariesProcessed: dictIndex,
            dictionariesTotal: dictTotal,
          );
        },
        onProgress: (processed, total) {
          state = state.copyWith(
            processedEntries: processed,
            totalEntries: total,
          );
        },
        onDictionarySkipped: (name) {
          skipped.add(name);
          state = state.copyWith(skippedDictionaries: List.of(skipped));
        },
      );

      final parts = <String>[];
      if (result.importedDictionaries.isNotEmpty) {
        parts.add(
          'Imported ${result.importedDictionaries.length} '
          'dictionaries (${result.totalEntriesImported} entries)',
        );
      }
      if (result.skippedDictionaries.isNotEmpty) {
        parts.add(
          'Skipped ${result.skippedDictionaries.length} already imported: '
          '${result.skippedDictionaries.join(", ")}',
        );
      }
      if (parts.isEmpty) {
        parts.add('No dictionaries found in collection');
      }

      Sentry.addBreadcrumb(Breadcrumb(
        message: 'Dictionary collection imported '
            '(${result.importedDictionaries.length} dictionaries, '
            '${result.totalEntriesImported} entries)',
        category: 'dictionary',
      ));
      state = DictionaryImportState(
        successMessage: parts.join('. '),
        skippedDictionaries: result.skippedDictionaries,
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
