import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/manga/data/services/model_download_job.dart'
    show JobWait;
import 'package:mekuru/features/word_audio/data/services/word_audio.dart';
import 'package:mekuru/shared/downloads/download.dart'
    show TileOutcome, TileAction;

final wordAudioProvider = Provider<WordAudio>((ref) {
  final audio = WordAudio();
  ref.onDispose(audio.dispose);
  return audio;
});

/// Where the offline pack stands. [fraction] is set while it downloads, and
/// [wait] says what its Android job waits for. [outcome] is the last
/// download or remove (none after a cancel).
typedef WordAudioPackState = ({
  bool installed,
  bool hasFiles,
  double? fraction,
  JobWait wait,
  TileOutcome? outcome,
});

WordAudioPackState _packState({
  bool installed = false,
  bool hasFiles = false,
  double? fraction,
  JobWait wait = JobWait.none,
  TileOutcome? outcome,
}) => (
  installed: installed,
  hasFiles: hasFiles,
  fraction: fraction,
  wait: wait,
  outcome: outcome,
);

/// The offline pack's download, kept here so leaving Downloads doesn't lose it.
class WordAudioPackNotifier extends Notifier<WordAudioPackState> {
  /// [cancel] stopped the transfer, so the error that follows is the cancel.
  var _cancelling = false;

  /// Bumped when [start] or [remove] finishes, so a [refresh] that was already
  /// checking the disk doesn't overwrite their newer state.
  var _epoch = 0;

  @override
  WordAudioPackState build() {
    unawaited(refresh());
    return _packState();
  }

  Future<void> refresh() async {
    final epoch = _epoch;
    final pack = ref.read(wordAudioProvider).pack;
    // No app directory (widget tests): the row just offers the download.
    final (pending, installed, hasFiles) = await () async {
      try {
        return (
          await pack.pending(),
          await pack.installed,
          await pack.hasFiles(),
        );
      } catch (_) {
        return (false, false, false);
      }
    }();
    if (epoch != _epoch || state.fraction != null) return;
    // The Android job outlives the app: follow it. Following asks nothing, so
    // it never adds mobile data.
    if (pending) {
      unawaited(start(NetworkConsent.wifiOnly));
      return;
    }
    state = _packState(installed: installed, hasFiles: hasFiles);
  }

  /// Downloads the pack and the word list that goes with it, both over mobile
  /// data only when [network] allows it.
  Future<void> start(NetworkConsent network) async {
    if (state.fraction != null) return;
    _cancelling = false;
    final audio = ref.read(wordAudioProvider);
    state = _packState(hasFiles: true, fraction: 0);
    try {
      if (!await audio.installed) await audio.download(network: network);
      await audio.pack.download(
        network: network,
        onProgress: (fraction, wait) =>
            state = _packState(hasFiles: true, fraction: fraction, wait: wait),
      );
      logUsage('word_audio.pack_downloaded');
      state = _packState(
        installed: true,
        hasFiles: true,
        outcome: (action: TileAction.download, error: null),
      );
    } catch (e) {
      final hasFiles = await audio.pack.hasFiles();
      // Decided by the flag, not the error: a cancel surfaces as whatever the
      // closed connection threw.
      if (!_cancelling) logFailure('word_audio.pack_download_failed', e);
      state = _packState(
        hasFiles: hasFiles,
        outcome: _cancelling ? null : (action: TileAction.download, error: e),
      );
    } finally {
      _cancelling = false;
      _epoch++;
    }
  }

  /// Stops the download; the next [start] resumes it.
  void cancel() {
    if (state.fraction == null) return;
    _cancelling = ref.read(wordAudioProvider).pack.cancel();
  }

  /// Deletes the pack. Ignored while downloading: deleting the folder would
  /// only unlink the open partial file under the running transfer.
  Future<void> remove() async {
    if (state.fraction != null) return;
    try {
      await ref.read(wordAudioProvider).pack.delete();
      state = _packState(outcome: (action: TileAction.delete, error: null));
    } catch (e) {
      logFailure('word_audio.pack_delete_failed', e);
      // Its files are still there, so the row keeps Remove to try again.
      state = _packState(
        installed: state.installed,
        hasFiles: state.hasFiles,
        outcome: (action: TileAction.delete, error: e),
      );
    } finally {
      _epoch++;
    }
  }
}

final wordAudioPackProvider =
    NotifierProvider<WordAudioPackNotifier, WordAudioPackState>(
      WordAudioPackNotifier.new,
    );
