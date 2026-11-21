import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/models/dictionary_catalog.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_importer.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_query_service.dart';
import 'package:mekuru/core/services/sentry_helpers.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/main.dart' show databaseProvider;

// ──────────────── Repository & Services ────────────────

/// Provider for the dictionary repository.
final dictionaryRepositoryProvider = Provider<DictionaryRepository>((ref) {
  return DictionaryRepository(ref.watch(databaseProvider));
});

/// An image from a dictionary zip, keyed by (dictionary id, zip path); null
/// when the dictionary has no image there.
final dictionaryMediaProvider = FutureProvider.autoDispose
    .family<Uint8List?, (int, String)>(
      (ref, key) =>
          ref.watch(dictionaryRepositoryProvider).getMedia(key.$1, key.$2),
    );

/// Provider for the dictionary query service.
/// Watches the reactive dictionary stream to invalidate the metadata cache
/// whenever dictionaries are toggled, reordered, deleted, or imported.
final dictionaryQueryServiceProvider = Provider<DictionaryQueryService>((ref) {
  final service = DictionaryQueryService(ref.watch(databaseProvider));
  // Listen to dictionary changes and invalidate the metadata cache.
  ref.listen(dictionariesProvider, (_, _) {
    service.invalidateMetasCache();
  });
  return service;
});

/// Provider for the dictionary importer.
final dictionaryImporterProvider = Provider<DictionaryImporter>((ref) {
  return DictionaryImporter(ref.watch(dictionaryRepositoryProvider));
});

// ──────────────── Data Providers ────────────────

/// Reactive stream of the dictionaries the dictionary manager lists.
final dictionariesProvider = StreamProvider<List<DictionaryMeta>>((ref) {
  return ref.watch(dictionaryRepositoryProvider).watchVisibleDictionaries();
});

/// Whether a dictionary only ranks other dictionaries' words. Asked once per
/// dictionary: what one holds is fixed at import. For the dictionary manager
/// only: its query can read the whole entry index.
final frequencyOnlyDictionaryProvider = FutureProvider.family<bool, int>(
  (ref, id) => ref.watch(dictionaryRepositoryProvider).isFrequencyOnly(id),
);

/// Whether the listed dictionaries can answer a lookup. A frequency
/// dictionary such as JPDB only ranks the others' words, so it never counts.
enum LookupDictionaries {
  /// None can: there are none, or they only rank words.
  none,

  /// Some can, and all of those are switched off.
  allOff,

  /// One that can is switched on.
  ready,
}

/// What the listed dictionaries allow. Its query can read the whole entry
/// index, so watch it only while no search is waiting on the database.
final lookupDictionariesProvider = FutureProvider<LookupDictionaries>((
  ref,
) async {
  final repository = ref.watch(dictionaryRepositoryProvider);
  final dictionaries = await ref.watch(dictionariesProvider.future);
  Future<bool> anyAnswers({required bool on}) => repository.anyAnswersLookups([
    for (final d in dictionaries)
      if (d.isEnabled == on) d.id,
  ]);
  if (await anyAnswers(on: true)) return LookupDictionaries.ready;
  if (await anyAnswers(on: false)) return LookupDictionaries.allOff;
  return LookupDictionaries.none;
});

// ──────────────── Import State ────────────────

/// A stretch of an import with no entry count to show.
enum DictionaryImportStep {
  /// A collection's file is read, before its dictionaries import.
  parsingCollection,

  /// Every entry is stored; the search index is built and the import saved.
  finishing,
}

/// What an import added: its entries, and for a collection its dictionaries
/// (null for a single dictionary).
typedef DictionaryImportResult = ({int entries, int? dictionaries});

/// State for dictionary import progress. The screen words it.
class DictionaryImportState {
  final bool isImporting;
  final int processedEntries;
  final int totalEntries;

  /// The name of the collection's dictionary being imported.
  final String? currentDictionary;
  final DictionaryImportStep? step;
  final int dictionariesProcessed;
  final int dictionariesTotal;

  /// Why the last import failed.
  final Object? failure;

  /// What the last import added, when it worked.
  final DictionaryImportResult? imported;

  const DictionaryImportState({
    this.isImporting = false,
    this.processedEntries = 0,
    this.totalEntries = 0,
    this.currentDictionary,
    this.step,
    this.dictionariesProcessed = 0,
    this.dictionariesTotal = 0,
    this.failure,
    this.imported,
  });

  double get progress => totalEntries > 0 ? processedEntries / totalEntries : 0;

  DictionaryImportState copyWith({
    bool? isImporting,
    int? processedEntries,
    int? totalEntries,
    String? currentDictionary,
    DictionaryImportStep? step,
    int? dictionariesProcessed,
    int? dictionariesTotal,
  }) {
    return DictionaryImportState(
      isImporting: isImporting ?? this.isImporting,
      processedEntries: processedEntries ?? this.processedEntries,
      totalEntries: totalEntries ?? this.totalEntries,
      currentDictionary: currentDictionary ?? this.currentDictionary,
      step: step ?? this.step,
      dictionariesProcessed:
          dictionariesProcessed ?? this.dictionariesProcessed,
      dictionariesTotal: dictionariesTotal ?? this.dictionariesTotal,
      failure: failure,
      imported: imported,
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
      final count = await tracedOperation(
        'dictionary.import_duration_ms',
        action: () => importer.importFromFile(
          filePath,
          onProgress: (processed, total) {
            state = state.copyWith(
              processedEntries: processed,
              totalEntries: total,
            );
          },
          onFinishing: () =>
              state = state.copyWith(step: DictionaryImportStep.finishing),
        ),
      );
      logUsage('dictionary.imported', attrs: {'entry_count': count});
      countUsage('dictionary.imported');
      state = DictionaryImportState(
        imported: (entries: count, dictionaries: null),
      );
    } catch (e) {
      // tracedOperation logged it.
      state = DictionaryImportState(failure: e);
    }
  }

  Future<void> _importCollection(String filePath) async {
    state = const DictionaryImportState(isImporting: true);

    try {
      final importer = ref.read(dictionaryImporterProvider);
      final result = await tracedOperation(
        'dictionary.collection_import_duration_ms',
        action: () => importer.importCollectionFromFile(
          filePath,
          onParsing: () {
            state = state.copyWith(
              step: DictionaryImportStep.parsingCollection,
            );
          },
          onDictionaryStart: (name, entryCount, dictIndex, dictTotal) {
            state = state.copyWith(
              currentDictionary: dictionaryDisplayName(name),
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
        ),
      );

      logUsage(
        'dictionary.collection_imported',
        attrs: {
          'dict_count': result.importedDictionaries.length,
          'entry_count': result.totalEntriesImported,
        },
      );
      countUsage('dictionary.collection_imported');
      state = DictionaryImportState(
        imported: (
          entries: result.totalEntriesImported,
          dictionaries: result.importedDictionaries.length,
        ),
      );
    } catch (e) {
      // tracedOperation logged it.
      state = DictionaryImportState(failure: e);
    }
  }
}

final dictionaryImportProvider =
    NotifierProvider<DictionaryImportNotifier, DictionaryImportState>(
      DictionaryImportNotifier.new,
    );
