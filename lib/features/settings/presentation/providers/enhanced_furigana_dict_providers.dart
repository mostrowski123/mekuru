import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/features/settings/data/services/enhanced_furigana_dict_download_service.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/shared/downloads/download.dart';

class EnhancedFuriganaDictState {
  final bool isInstalled;
  final bool isDownloading;
  final bool isUninstalling;
  final double progress;

  /// The last download or removal, until the next state change.
  final TileOutcome? outcome;

  const EnhancedFuriganaDictState({
    this.isInstalled = false,
    this.isDownloading = false,
    this.isUninstalling = false,
    this.progress = 0.0,
    this.outcome,
  });

  EnhancedFuriganaDictState copyWith({
    bool? isInstalled,
    bool? isDownloading,
    bool? isUninstalling,
    double? progress,
    TileOutcome? outcome,
  }) {
    return EnhancedFuriganaDictState(
      isInstalled: isInstalled ?? this.isInstalled,
      isDownloading: isDownloading ?? this.isDownloading,
      isUninstalling: isUninstalling ?? this.isUninstalling,
      progress: progress ?? this.progress,
      outcome: outcome,
    );
  }
}

class EnhancedFuriganaDictNotifier extends Notifier<EnhancedFuriganaDictState> {
  @override
  EnhancedFuriganaDictState build() => const EnhancedFuriganaDictState();

  Future<void> checkStatus() async {
    try {
      final installed = await EnhancedFuriganaDictDownloadService.isInstalled();
      state = state.copyWith(isInstalled: installed);
    } catch (e) {
      debugPrint('[EnhancedFurigana] Error checking status: $e');
    }
  }

  Future<void> download(NetworkConsent network) async {
    if (state.isDownloading) return;
    state = state.copyWith(isDownloading: true, progress: 0.0);

    try {
      await EnhancedFuriganaDictDownloadService.downloadAndInstall(
        network: network,
        onProgress: (p) {
          state = state.copyWith(progress: p);
        },
      );
      ref.read(enhancedFuriganaDictEnabledProvider.notifier).setEnabled(true);
      state = const EnhancedFuriganaDictState(
        isInstalled: true,
        outcome: (action: TileAction.download, error: null),
      );
    } catch (e) {
      // The archive goes with the failure, so the next tap starts over.
      state = EnhancedFuriganaDictState(
        isInstalled: state.isInstalled,
        outcome: (action: TileAction.download, error: e),
      );
    }
  }

  Future<void> uninstall() async {
    if (state.isUninstalling) return;
    state = state.copyWith(isUninstalling: true);

    try {
      await EnhancedFuriganaDictDownloadService.uninstall();
      ref.read(enhancedFuriganaDictEnabledProvider.notifier).setEnabled(false);
      state = const EnhancedFuriganaDictState(
        outcome: (action: TileAction.delete, error: null),
      );
    } catch (e) {
      state = state.copyWith(
        isUninstalling: false,
        outcome: (action: TileAction.delete, error: e),
      );
    }
  }
}

final enhancedFuriganaDictProvider =
    NotifierProvider<EnhancedFuriganaDictNotifier, EnhancedFuriganaDictState>(
      EnhancedFuriganaDictNotifier.new,
    );
