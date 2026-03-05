import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/features/settings/data/services/jpdb_freq_download_service.dart';

/// State for JPDB frequency dictionary management.
class JpdbFreqState {
  final bool isImported;
  final bool isDownloading;
  final bool isDeleting;
  final double progress;
  final String? error;
  final String? successMessage;

  const JpdbFreqState({
    this.isImported = false,
    this.isDownloading = false,
    this.isDeleting = false,
    this.progress = 0.0,
    this.error,
    this.successMessage,
  });

  JpdbFreqState copyWith({
    bool? isImported,
    bool? isDownloading,
    bool? isDeleting,
    double? progress,
    String? error,
    String? successMessage,
  }) {
    return JpdbFreqState(
      isImported: isImported ?? this.isImported,
      isDownloading: isDownloading ?? this.isDownloading,
      isDeleting: isDeleting ?? this.isDeleting,
      progress: progress ?? this.progress,
      error: error,
      successMessage: successMessage,
    );
  }
}

/// Notifier for managing JPDB frequency dictionary download state.
class JpdbFreqNotifier extends Notifier<JpdbFreqState> {
  @override
  JpdbFreqState build() => const JpdbFreqState();

  /// Check whether the JPDB frequency dictionary is imported.
  Future<void> checkStatus() async {
    try {
      final repository = ref.read(dictionaryRepositoryProvider);
      final imported = await JpdbFreqDownloadService.isImported(repository);
      state = state.copyWith(isImported: imported);
    } catch (e) {
      debugPrint('[JpdbFreq] Error checking status: $e');
    }
  }

  /// Download and import the JPDB frequency dictionary.
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
      await JpdbFreqDownloadService.downloadAndImport(
        repository: repository,
        importer: importer,
        onProgress: (progress) {
          state = state.copyWith(progress: progress);
        },
      );
      state = const JpdbFreqState(
        isImported: true,
        successMessage: 'Frequency dictionary downloaded successfully.',
      );
    } catch (e) {
      state = JpdbFreqState(
        isImported: state.isImported,
        error: 'Download failed: $e',
      );
    }
  }

  /// Delete the JPDB frequency dictionary.
  Future<void> delete() async {
    if (state.isDeleting) return;
    state = state.copyWith(isDeleting: true, error: null, successMessage: null);

    try {
      final repository = ref.read(dictionaryRepositoryProvider);
      await JpdbFreqDownloadService.delete(repository);
      state = const JpdbFreqState(
        successMessage: 'Frequency dictionary deleted.',
      );
    } catch (e) {
      state = state.copyWith(isDeleting: false, error: 'Delete failed: $e');
    }
  }
}

final jpdbFreqProvider = NotifierProvider<JpdbFreqNotifier, JpdbFreqState>(
  JpdbFreqNotifier.new,
);
