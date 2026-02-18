import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/features/settings/data/services/yomitan_dict_download_service.dart';

/// State for KANJIDIC dictionary management.
class KanjidicState {
  final bool isImported;
  final bool isDownloading;
  final bool isDeleting;
  final double progress;
  final String? error;
  final String? successMessage;

  const KanjidicState({
    this.isImported = false,
    this.isDownloading = false,
    this.isDeleting = false,
    this.progress = 0.0,
    this.error,
    this.successMessage,
  });

  KanjidicState copyWith({
    bool? isImported,
    bool? isDownloading,
    bool? isDeleting,
    double? progress,
    String? error,
    String? successMessage,
  }) {
    return KanjidicState(
      isImported: isImported ?? this.isImported,
      isDownloading: isDownloading ?? this.isDownloading,
      isDeleting: isDeleting ?? this.isDeleting,
      progress: progress ?? this.progress,
      error: error,
      successMessage: successMessage,
    );
  }
}

/// Notifier for managing KANJIDIC dictionary download state.
class KanjidicNotifier extends Notifier<KanjidicState> {
  @override
  KanjidicState build() => const KanjidicState();

  /// Check whether KANJIDIC is already imported.
  Future<void> checkStatus() async {
    try {
      final repository = ref.read(dictionaryRepositoryProvider);
      final imported = await YomitanDictDownloadService.isImported(
        YomitanDictType.kanjidicEnglish,
        repository,
      );
      state = state.copyWith(isImported: imported);
    } catch (e) {
      debugPrint('[KANJIDIC] Error checking status: $e');
    }
  }

  /// Download and import KANJIDIC.
  Future<void> download() async {
    if (state.isDownloading) return;
    state = state.copyWith(
      isDownloading: true,
      progress: 0.0,
      error: null,
      successMessage: null,
    );

    try {
      final repository = ref.read(dictionaryRepositoryProvider);
      final importer = ref.read(dictionaryImporterProvider);
      await YomitanDictDownloadService.downloadAndImport(
        type: YomitanDictType.kanjidicEnglish,
        repository: repository,
        importer: importer,
        onProgress: (progress) {
          state = state.copyWith(progress: progress);
        },
      );
      state = const KanjidicState(
        isImported: true,
        successMessage: 'KANJIDIC downloaded successfully.',
      );
    } catch (e) {
      state = KanjidicState(
        isImported: state.isImported,
        error: 'Download failed: $e',
      );
    }
  }

  /// Delete the KANJIDIC dictionary.
  Future<void> delete() async {
    if (state.isDeleting) return;
    state = state.copyWith(isDeleting: true, error: null, successMessage: null);

    try {
      final repository = ref.read(dictionaryRepositoryProvider);
      await YomitanDictDownloadService.delete(
        YomitanDictType.kanjidicEnglish,
        repository,
      );
      state = const KanjidicState(
        successMessage: 'KANJIDIC deleted.',
      );
    } catch (e) {
      state = state.copyWith(
        isDeleting: false,
        error: 'Delete failed: $e',
      );
    }
  }
}

final kanjidicProvider = NotifierProvider<KanjidicNotifier, KanjidicState>(
  KanjidicNotifier.new,
);
