import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/settings/data/services/kanjivg_download_service.dart';

/// State for KanjiVG asset management.
class KanjiVgState {
  final bool isDownloaded;
  final bool isDownloading;
  final bool isDeleting;
  final double progress;
  final int fileCount;
  final String? error;
  final String? successMessage;

  const KanjiVgState({
    this.isDownloaded = false,
    this.isDownloading = false,
    this.isDeleting = false,
    this.progress = 0.0,
    this.fileCount = 0,
    this.error,
    this.successMessage,
  });

  KanjiVgState copyWith({
    bool? isDownloaded,
    bool? isDownloading,
    bool? isDeleting,
    double? progress,
    int? fileCount,
    String? error,
    String? successMessage,
  }) {
    return KanjiVgState(
      isDownloaded: isDownloaded ?? this.isDownloaded,
      isDownloading: isDownloading ?? this.isDownloading,
      isDeleting: isDeleting ?? this.isDeleting,
      progress: progress ?? this.progress,
      fileCount: fileCount ?? this.fileCount,
      error: error,
      successMessage: successMessage,
    );
  }
}

/// Notifier for managing KanjiVG download state.
class KanjiVgNotifier extends Notifier<KanjiVgState> {
  @override
  KanjiVgState build() => const KanjiVgState();

  /// Check whether KanjiVG files are already present on disk.
  Future<void> checkStatus() async {
    try {
      final downloaded = await KanjiVgDownloadService.isDownloaded();
      final count = downloaded ? await KanjiVgDownloadService.fileCount() : 0;
      state = state.copyWith(isDownloaded: downloaded, fileCount: count);
    } catch (e) {
      debugPrint('[KanjiVG] Error checking status: $e');
    }
  }

  /// Download and extract KanjiVG SVGs from GitHub.
  Future<void> download() async {
    if (state.isDownloading) return;
    state = state.copyWith(
      isDownloading: true,
      progress: 0.0,
      error: null,
      successMessage: null,
    );

    try {
      final count = await KanjiVgDownloadService.downloadAndExtract(
        onProgress: (progress) {
          state = state.copyWith(progress: progress);
        },
      );
      state = KanjiVgState(
        isDownloaded: true,
        fileCount: count,
        successMessage: 'Downloaded $count kanji stroke order files.',
      );
    } catch (e) {
      state = KanjiVgState(
        isDownloaded: state.isDownloaded,
        fileCount: state.fileCount,
        error: 'Download failed: $e',
      );
    }
  }

  /// Delete all downloaded KanjiVG files.
  Future<void> delete() async {
    if (state.isDeleting) return;
    state = state.copyWith(isDeleting: true, error: null, successMessage: null);

    try {
      await KanjiVgDownloadService.delete();
      state = const KanjiVgState(successMessage: 'Kanji stroke data deleted.');
    } catch (e) {
      state = state.copyWith(isDeleting: false, error: 'Delete failed: $e');
    }
  }

  /// Clear any transient error/success messages.
  void clearMessages() {
    state = state.copyWith(error: null, successMessage: null);
  }
}

final kanjiVgProvider = NotifierProvider<KanjiVgNotifier, KanjiVgState>(
  KanjiVgNotifier.new,
);
