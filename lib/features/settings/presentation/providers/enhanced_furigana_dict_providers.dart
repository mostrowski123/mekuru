import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/features/settings/data/services/enhanced_furigana_dict_download_service.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/shared/downloads/download_tile_state.dart';

/// Downloads, finds and deletes UniDic-lite, and switches it on or off with
/// it.
class EnhancedFuriganaDictNotifier extends DownloadTileNotifier {
  @override
  Future<void> checkStatus() => checking(
    'EnhancedFurigana',
    () async => (
      installed: await EnhancedFuriganaDictDownloadService.isInstalled(),
      fileCount: 0,
    ),
  );

  /// The archive goes with a failure, so the next tap starts over.
  @override
  Future<void> download(NetworkConsent network) =>
      downloading((onProgress) async {
        await EnhancedFuriganaDictDownloadService.downloadAndInstall(
          network: network,
          onProgress: onProgress,
        );
        ref.read(enhancedFuriganaDictEnabledProvider.notifier).setEnabled(true);
        return 0;
      });

  @override
  Future<void> delete() => deleting(() async {
    await EnhancedFuriganaDictDownloadService.uninstall();
    ref.read(enhancedFuriganaDictEnabledProvider.notifier).setEnabled(false);
  });
}

final enhancedFuriganaDictProvider =
    NotifierProvider<EnhancedFuriganaDictNotifier, DownloadTileState>(
      EnhancedFuriganaDictNotifier.new,
    );
