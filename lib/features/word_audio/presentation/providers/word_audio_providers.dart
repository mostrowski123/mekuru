import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/word_audio/data/services/word_audio.dart';

final wordAudioProvider = Provider<WordAudio>((ref) {
  final audio = WordAudio();
  ref.onDispose(audio.dispose);
  return audio;
});

/// Where the offline pack stands. [fraction] is set while it downloads.
typedef WordAudioPackState = ({
  bool installed,
  bool hasFiles,
  double? fraction,
  Object? error,
});

WordAudioPackState _packState({
  bool installed = false,
  bool hasFiles = false,
  double? fraction,
  Object? error,
}) => (
  installed: installed,
  hasFiles: hasFiles,
  fraction: fraction,
  error: error,
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
    // The Android job outlives the app: follow it.
    if (pending) {
      unawaited(start());
      return;
    }
    state = _packState(installed: installed, hasFiles: hasFiles);
  }

  /// Downloads the pack and the word list that goes with it. Over mobile data
  /// only with [mobileData], which the user agreed to: following a job after a
  /// relaunch never adds it.
  Future<void> start({bool mobileData = false}) async {
    if (state.fraction != null) return;
    _cancelling = false;
    final audio = ref.read(wordAudioProvider);
    state = _packState(hasFiles: true, fraction: 0);
    try {
      if (!await audio.installed) await audio.download(wifiOnly: !mobileData);
      await audio.pack.download(
        mobileData: mobileData,
        onProgress: (fraction) =>
            state = _packState(hasFiles: true, fraction: fraction),
      );
      logUsage('word_audio.pack_downloaded');
      state = _packState(installed: true, hasFiles: true);
    } catch (e) {
      final hasFiles = await audio.pack.hasFiles();
      // Decided by the flag, not the error: a cancel surfaces as whatever the
      // closed connection threw.
      if (!_cancelling) logFailure('word_audio.pack_download_failed', e);
      state = _packState(hasFiles: hasFiles, error: _cancelling ? null : e);
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
    await ref.read(wordAudioProvider).pack.delete();
    _epoch++;
    state = _packState();
  }
}

final wordAudioPackProvider =
    NotifierProvider<WordAudioPackNotifier, WordAudioPackState>(
      WordAudioPackNotifier.new,
    );
