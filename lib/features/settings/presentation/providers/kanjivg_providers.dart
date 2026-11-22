import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/features/settings/data/services/kanjivg_download_service.dart';
import 'package:mekuru/shared/downloads/download_tile_state.dart';

/// Downloads, finds and deletes the KanjiVG stroke order SVGs; the state
/// counts them.
class KanjiVgNotifier extends DownloadTileNotifier {
  /// Check whether KanjiVG files are already present on disk.
  @override
  Future<void> checkStatus() => checking('KanjiVG', () async {
    final downloaded = await KanjiVgDownloadService.isDownloaded();
    return (
      installed: downloaded,
      fileCount: downloaded ? await KanjiVgDownloadService.fileCount() : 0,
    );
  });

  /// Download and extract KanjiVG SVGs from GitHub over [network]. The
  /// archive goes with a failure, so the next tap starts over.
  @override
  Future<void> download(NetworkConsent network) => downloading(
    (onProgress) => KanjiVgDownloadService.downloadAndExtract(
      network: network,
      onProgress: onProgress,
    ),
  );

  /// Delete all downloaded KanjiVG files.
  @override
  Future<void> delete() => deleting(KanjiVgDownloadService.delete);
}

final kanjiVgProvider = NotifierProvider<KanjiVgNotifier, DownloadTileState>(
  KanjiVgNotifier.new,
);
