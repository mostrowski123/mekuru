import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/shared/downloads/download.dart';

/// What a `DownloadTile` shows: a download that is installed, or on its way
/// in or out, and how its last download or delete went.
class DownloadTileState {
  const DownloadTileState({
    this.isInstalled = false,
    this.isDownloading = false,
    this.isDeleting = false,
    this.progress = 0.0,
    this.fileCount = 0,
    this.outcome,
  });

  final bool isInstalled;
  final bool isDownloading;
  final bool isDeleting;
  final double progress;

  /// How many files it installed, where the tile counts them (KanjiVG's
  /// SVGs); 0 elsewhere.
  final int fileCount;

  /// The last download or delete, until the next state change.
  final TileOutcome? outcome;

  /// This state changed as given, which ends what [outcome] said.
  DownloadTileState copyWith({
    bool? isInstalled,
    bool? isDownloading,
    bool? isDeleting,
    double? progress,
    int? fileCount,
    TileOutcome? outcome,
  }) => DownloadTileState(
    isInstalled: isInstalled ?? this.isInstalled,
    isDownloading: isDownloading ?? this.isDownloading,
    isDeleting: isDeleting ?? this.isDeleting,
    progress: progress ?? this.progress,
    fileCount: fileCount ?? this.fileCount,
    outcome: outcome,
  );
}

/// Finds, downloads and deletes what one `DownloadTile` shows. A subclass
/// says how, through [checking], [downloading] and [deleting].
abstract class DownloadTileNotifier extends Notifier<DownloadTileState> {
  @override
  DownloadTileState build() => const DownloadTileState();

  /// Whether it is installed already.
  Future<void> checkStatus();

  /// Downloads and installs it over [network].
  Future<void> download(NetworkConsent network);

  Future<void> delete();

  /// [checkStatus] through [find]: whether it is installed, and its
  /// [DownloadTileState.fileCount]. A failure only goes to the debug log,
  /// tagged [logTag].
  @protected
  Future<void> checking(
    String logTag,
    Future<({bool installed, int fileCount})> Function() find,
  ) async {
    try {
      final found = await find();
      state = state.copyWith(
        isInstalled: found.installed,
        fileCount: found.fileCount,
      );
    } catch (e) {
      debugPrint('[$logTag] Error checking status: $e');
    }
  }

  /// [download] through [install], which reports progress and returns the
  /// [DownloadTileState.fileCount]. Ignored while a download runs.
  @protected
  Future<void> downloading(
    Future<int> Function(void Function(double progress) onProgress) install,
  ) async {
    if (state.isDownloading) return;
    state = state.copyWith(isDownloading: true, progress: 0.0);

    try {
      final count = await install(
        (progress) => state = state.copyWith(progress: progress),
      );
      state = DownloadTileState(
        isInstalled: true,
        fileCount: count,
        outcome: (action: TileAction.download, error: null),
      );
    } catch (e) {
      state = DownloadTileState(
        isInstalled: state.isInstalled,
        fileCount: state.fileCount,
        outcome: (action: TileAction.download, error: e),
      );
    }
  }

  /// [delete] through [uninstall]. Ignored while a delete runs.
  @protected
  Future<void> deleting(Future<void> Function() uninstall) async {
    if (state.isDeleting) return;
    state = state.copyWith(isDeleting: true);

    try {
      await uninstall();
      state = const DownloadTileState(
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
