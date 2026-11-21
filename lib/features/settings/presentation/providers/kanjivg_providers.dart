import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/features/settings/data/services/kanjivg_download_service.dart';
import 'package:mekuru/shared/downloads/download.dart';

/// State for KanjiVG asset management.
class KanjiVgState {
  final bool isDownloaded;
  final bool isDownloading;
  final bool isDeleting;
  final double progress;
  final int fileCount;

  /// The last download or delete, until the next state change.
  final TileOutcome? outcome;

  const KanjiVgState({
    this.isDownloaded = false,
    this.isDownloading = false,
    this.isDeleting = false,
    this.progress = 0.0,
    this.fileCount = 0,
    this.outcome,
  });

  KanjiVgState copyWith({
    bool? isDownloaded,
    bool? isDownloading,
    bool? isDeleting,
    double? progress,
    int? fileCount,
    TileOutcome? outcome,
  }) {
    return KanjiVgState(
      isDownloaded: isDownloaded ?? this.isDownloaded,
      isDownloading: isDownloading ?? this.isDownloading,
      isDeleting: isDeleting ?? this.isDeleting,
      progress: progress ?? this.progress,
      fileCount: fileCount ?? this.fileCount,
      outcome: outcome,
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

  /// Download and extract KanjiVG SVGs from GitHub over [network].
  Future<void> download(NetworkConsent network) async {
    if (state.isDownloading) return;
    state = state.copyWith(isDownloading: true, progress: 0.0);

    try {
      final count = await KanjiVgDownloadService.downloadAndExtract(
        network: network,
        onProgress: (progress) {
          state = state.copyWith(progress: progress);
        },
      );
      state = KanjiVgState(
        isDownloaded: true,
        fileCount: count,
        outcome: (action: TileAction.download, error: null),
      );
    } catch (e) {
      // The archive goes with the failure, so the next tap starts over.
      state = KanjiVgState(
        isDownloaded: state.isDownloaded,
        fileCount: state.fileCount,
        outcome: (action: TileAction.download, error: e),
      );
    }
  }

  /// Delete all downloaded KanjiVG files.
  Future<void> delete() async {
    if (state.isDeleting) return;
    state = state.copyWith(isDeleting: true);

    try {
      await KanjiVgDownloadService.delete();
      state = const KanjiVgState(
        outcome: (action: TileAction.delete, error: null),
      );
    } catch (e) {
      state = state.copyWith(
        isDeleting: false,
        outcome: (action: TileAction.delete, error: e),
      );
    }
  }
}

final kanjiVgProvider = NotifierProvider<KanjiVgNotifier, KanjiVgState>(
  KanjiVgNotifier.new,
);
