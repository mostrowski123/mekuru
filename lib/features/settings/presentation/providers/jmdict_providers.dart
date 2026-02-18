import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/features/settings/data/services/yomitan_dict_download_service.dart';

/// State for JMdict dictionary management.
class JmdictState {
  final bool isImported;
  final bool isDownloading;
  final bool isDeleting;
  final double progress;
  final String? error;
  final String? successMessage;

  const JmdictState({
    this.isImported = false,
    this.isDownloading = false,
    this.isDeleting = false,
    this.progress = 0.0,
    this.error,
    this.successMessage,
  });

  JmdictState copyWith({
    bool? isImported,
    bool? isDownloading,
    bool? isDeleting,
    double? progress,
    String? error,
    String? successMessage,
  }) {
    return JmdictState(
      isImported: isImported ?? this.isImported,
      isDownloading: isDownloading ?? this.isDownloading,
      isDeleting: isDeleting ?? this.isDeleting,
      progress: progress ?? this.progress,
      error: error,
      successMessage: successMessage,
    );
  }
}

/// Notifier for managing JMdict dictionary download state.
class JmdictNotifier extends Notifier<JmdictState> {
  @override
  JmdictState build() => const JmdictState();

  /// Check whether JMdict is already imported.
  Future<void> checkStatus() async {
    try {
      final repository = ref.read(dictionaryRepositoryProvider);
      final imported = await YomitanDictDownloadService.isImported(
        YomitanDictType.jmdictEnglish,
        repository,
      );
      state = state.copyWith(isImported: imported);
    } catch (e) {
      debugPrint('[JMdict] Error checking status: $e');
    }
  }

  /// Download and import JMdict with the chosen variant.
  Future<void> download(YomitanDictType variant) async {
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
        type: variant,
        repository: repository,
        importer: importer,
        onProgress: (progress) {
          state = state.copyWith(progress: progress);
        },
      );
      state = const JmdictState(
        isImported: true,
        successMessage: 'JMdict downloaded successfully.',
      );
    } catch (e) {
      state = JmdictState(
        isImported: state.isImported,
        error: 'Download failed: $e',
      );
    }
  }

  /// Delete the JMdict dictionary.
  Future<void> delete() async {
    if (state.isDeleting) return;
    state = state.copyWith(isDeleting: true, error: null, successMessage: null);

    try {
      final repository = ref.read(dictionaryRepositoryProvider);
      await YomitanDictDownloadService.delete(
        YomitanDictType.jmdictEnglish,
        repository,
      );
      state = const JmdictState(
        successMessage: 'JMdict deleted.',
      );
    } catch (e) {
      state = state.copyWith(
        isDeleting: false,
        error: 'Delete failed: $e',
      );
    }
  }
}

final jmdictProvider = NotifierProvider<JmdictNotifier, JmdictState>(
  JmdictNotifier.new,
);
