import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/reader/data/services/gemma_translation.dart';
import 'package:mekuru/features/reader/data/services/sentence_translation.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';

sealed class GemmaDownloadState {
  const GemmaDownloadState();
}

class GemmaNotInstalled extends GemmaDownloadState {
  const GemmaNotInstalled({this.hasFiles = false});

  /// A partial download is on disk, which Remove can take away.
  final bool hasFiles;
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
  Future<bool> Function() hasFiles,
  bool Function() cancel,
  // A download job is queued or running, or one finished unseen.
  Future<bool> Function() pending,
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
      hasFiles: GemmaTranslation.instance.hasFiles,
      cancel: GemmaTranslation.instance.cancelDownload,
      pending: GemmaTranslation.instance.downloadPending,
    );

/// The Gemma model's download, shared by Settings, Downloads and the
/// Sentence tab so leaving a screen doesn't lose it. Not autoDispose for
/// the same reason.
class GemmaDownloadNotifier extends Notifier<GemmaDownloadState> {
  /// [cancel] closed the transfer, so the error that follows is the cancel.
  var _cancelling = false;

  /// [cancel] was called, whether or not it stopped anything: the user
  /// switched away, so a download that still finishes doesn't choose High.
  var _cancelRequested = false;

  /// Bumped when [start] or [remove] finishes, so a [refresh] that was
  /// already checking the disk doesn't overwrite their newer state.
  var _epoch = 0;

  @override
  GemmaDownloadState build() {
    unawaited(refresh());
    return const GemmaNotInstalled();
  }

  Future<void> refresh() async {
    // Checks the state only after the await: build() calls this before its
    // state exists, and a download may start while the check runs.
    final epoch = _epoch;
    final pending = await _ops.pending();
    final installed = await _ops.installed();
    final hasFiles = !installed && await _ops.hasFiles();
    if (epoch != _epoch || state is GemmaDownloading) return;
    // The download job outlives the app: follow it, or take the model it
    // installed while Mekuru was closed, choosing High like any download.
    if (pending) {
      unawaited(start());
      return;
    }
    _settle(
      installed
          ? const GemmaInstalled()
          : GemmaNotInstalled(hasFiles: hasFiles),
    );
  }

  /// Sets a finished state and keeps High quality chosen only while its
  /// model is installed: [select] (a finished [start]) chooses it, and a
  /// missing model drops it to Standard. Finding the model doesn't choose
  /// it, since Standard keeps the files.
  void _settle(GemmaDownloadState next, {bool select = false}) {
    state = next;
    if (next is GemmaInstalled && !select) return;
    final choice = next is GemmaInstalled
        ? TranslationModelChoice.high
        : TranslationModelChoice.standard;
    if (ref.read(translationModelProvider) != choice) {
      ref.read(translationModelProvider.notifier).setChoice(choice);
    }
  }

  /// Downloads the model, or only reports it installed when its files are
  /// still there (Standard keeps them, and build()'s check may not have
  /// answered yet).
  Future<void> start() async {
    if (state is GemmaDownloading) return;
    _cancelling = false;
    _cancelRequested = false;
    // Before the check, so a second start meanwhile is ignored.
    state = const GemmaDownloading(0);
    try {
      if (await _ops.installed()) {
        _settle(const GemmaInstalled(), select: !_cancelRequested);
        return;
      }
      // Cancelled during the check: nothing to stop yet, so don't start.
      if (_cancelRequested) {
        logUsage('translation.high_quality_download_cancelled');
        _settle(GemmaNotInstalled(hasFiles: await _ops.hasFiles()));
        return;
      }
      await _ops.download((fraction) => state = GemmaDownloading(fraction));
      logUsage('translation.high_quality_downloaded');
      _settle(const GemmaInstalled(), select: !_cancelRequested);
    } catch (e) {
      // Decided by the flag, not the error: a cancel surfaces as whatever the
      // closed connection threw.
      if (_cancelling) {
        _cancelling = false;
        logUsage('translation.high_quality_download_cancelled');
        // Still downloading meanwhile, so nothing else can change the state.
        _settle(GemmaNotInstalled(hasFiles: await _ops.hasFiles()));
        return;
      }
      logFailure('translation.high_quality_download_failed', e);
      _settle(GemmaDownloadFailed(e));
    } finally {
      _epoch++;
    }
  }

  /// Stops the download; the next [start] resumes it. A download that
  /// finishes anyway (a cancel that found nothing to stop, or came as the
  /// job ended) is installed but not chosen.
  void cancel() {
    if (state is! GemmaDownloading) return;
    _cancelRequested = true;
    _cancelling = _ops.cancel();
  }

  /// Deletes the model. Ignored while downloading: deleting the folder
  /// would only unlink the open partial file under the running transfer.
  Future<void> remove() async {
    if (state is GemmaDownloading) return;
    await _ops.delete();
    _epoch++;
    _settle(const GemmaNotInstalled());
  }
}

final gemmaDownloadProvider =
    NotifierProvider<GemmaDownloadNotifier, GemmaDownloadState>(
      GemmaDownloadNotifier.new,
    );
