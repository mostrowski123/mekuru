import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/settings/data/services/enhanced_furigana_dict_download_service.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';

class EnhancedFuriganaDictState {
  final bool isInstalled;
  final bool isDownloading;
  final bool isUninstalling;
  final double progress;
  final String? error;
  final String? successMessage;

  const EnhancedFuriganaDictState({
    this.isInstalled = false,
    this.isDownloading = false,
    this.isUninstalling = false,
    this.progress = 0.0,
    this.error,
    this.successMessage,
  });

  EnhancedFuriganaDictState copyWith({
    bool? isInstalled,
    bool? isDownloading,
    bool? isUninstalling,
    double? progress,
    String? error,
    String? successMessage,
  }) {
    return EnhancedFuriganaDictState(
      isInstalled: isInstalled ?? this.isInstalled,
      isDownloading: isDownloading ?? this.isDownloading,
      isUninstalling: isUninstalling ?? this.isUninstalling,
      progress: progress ?? this.progress,
      error: error,
      successMessage: successMessage,
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

  Future<void> download() async {
    if (state.isDownloading) return;
    state = state.copyWith(
      isDownloading: true,
      progress: 0.0,
      error: null,
      successMessage: null,
    );

    try {
      await EnhancedFuriganaDictDownloadService.downloadAndInstall(
        onProgress: (p) {
          state = state.copyWith(progress: p);
        },
      );
      ref.read(enhancedFuriganaDictEnabledProvider.notifier).setEnabled(true);
      state = const EnhancedFuriganaDictState(
        isInstalled: true,
        successMessage:
            'Enhanced dictionary installed. Restart the app to use it.',
      );
    } catch (e) {
      state = EnhancedFuriganaDictState(
        isInstalled: state.isInstalled,
        error: 'Download failed: $e',
      );
    }
  }

  Future<void> uninstall() async {
    if (state.isUninstalling) return;
    state = state.copyWith(
      isUninstalling: true,
      error: null,
      successMessage: null,
    );

    try {
      await EnhancedFuriganaDictDownloadService.uninstall();
      ref.read(enhancedFuriganaDictEnabledProvider.notifier).setEnabled(false);
      state = const EnhancedFuriganaDictState(
        successMessage:
            'Enhanced dictionary removed. Restart the app to switch back to '
            'the bundled dictionary.',
      );
    } catch (e) {
      state = state.copyWith(
        isUninstalling: false,
        error: 'Removal failed: $e',
      );
    }
  }

  void clearMessages() {
    state = state.copyWith(error: null, successMessage: null);
  }
}

final enhancedFuriganaDictProvider =
    NotifierProvider<EnhancedFuriganaDictNotifier, EnhancedFuriganaDictState>(
      EnhancedFuriganaDictNotifier.new,
    );
