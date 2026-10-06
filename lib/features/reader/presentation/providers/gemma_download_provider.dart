import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/reader/data/services/gemma_translation.dart';
import 'package:mekuru/features/reader/data/services/sentence_translation.dart';

sealed class GemmaDownloadState {
  const GemmaDownloadState();
}

class GemmaNotInstalled extends GemmaDownloadState {
  const GemmaNotInstalled();
}

class GemmaDownloading extends GemmaDownloadState {
  const GemmaDownloading(this.fraction);
  final double fraction;
}

class GemmaInstalled extends GemmaDownloadState {
  const GemmaInstalled();
}

class GemmaDownloadFailed extends GemmaDownloadState {
  const GemmaDownloadFailed(this.error);
  final Object error;
}

typedef GemmaModelOps = ({
  Future<bool> Function() installed,
  Future<void> Function(void Function(double fraction) onProgress) download,
  Future<void> Function() delete,
});

/// Replaces the real model files in tests.
@visibleForTesting
GemmaModelOps? debugGemmaModelOps;

GemmaModelOps get _ops =>
    debugGemmaModelOps ??
    (
      installed: () async =>
          await GemmaTranslation.instance.status('en') ==
          TranslationStatus.installed,
      download: (onProgress) =>
          GemmaTranslation.instance.downloadModel(onProgress: onProgress),
      delete: GemmaTranslation.instance.delete,
    );

/// The Gemma model's download, shared by Settings, Downloads and the
/// Sentence tab so leaving a screen doesn't lose it. Not autoDispose for
/// the same reason.
class GemmaDownloadNotifier extends Notifier<GemmaDownloadState> {
  @override
  GemmaDownloadState build() {
    unawaited(refresh());
    return const GemmaNotInstalled();
  }

  Future<void> refresh() async {
    // Checks the state only after the await: build() calls this before its
    // state exists, and a download may start while the check runs.
    final installed = await _ops.installed();
    if (state is GemmaDownloading) return;
    state = installed ? const GemmaInstalled() : const GemmaNotInstalled();
  }

  Future<void> start() async {
    if (state is GemmaDownloading) return;
    state = const GemmaDownloading(0);
    try {
      await _ops.download((fraction) => state = GemmaDownloading(fraction));
      logUsage('translation.high_quality_downloaded');
      state = const GemmaInstalled();
    } catch (e) {
      logFailure('translation.high_quality_download_failed', e);
      state = GemmaDownloadFailed(e);
    }
  }

  Future<void> remove() async {
    await _ops.delete();
    state = const GemmaNotInstalled();
  }
}

final gemmaDownloadProvider =
    NotifierProvider<GemmaDownloadNotifier, GemmaDownloadState>(
      GemmaDownloadNotifier.new,
    );
