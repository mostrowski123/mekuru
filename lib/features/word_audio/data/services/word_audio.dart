import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:mekuru/core/config/app_links.dart';
import 'package:mekuru/core/platform/ios_storage.dart';
import 'package:mekuru/core/services/download_to_file.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/manga/data/services/model_download.dart';
import 'package:mekuru/features/word_audio/data/services/word_audio_lookup.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The word list that says which clip speaks which word, pinned by size and
/// sha256. Uncompressed so [downloadModelFiles] takes it as it is.
const ModelFile wordAudioIndexFile = (
  name: 'word_audio_index_2026-07-27.sqlite',
  url: '${AppLinks.wordAudioBase}/word_audio_index_2026-07-27.sqlite',
  bytes: 25939968,
  sha256: 'da195e99820f43215477c6ba060462d0bc8a552044513f105ca92d7a187e5059',
);

/// A clip's file on this device, and where it came from for telemetry.
typedef WordAudioClip = ({String path, String source});

/// The platform's player couldn't play a clip's file.
class WordAudioPlaybackException implements Exception {
  const WordAudioPlaybackException();
}

/// Spoken word audio: finds a word's clip, fetches it once and plays it.
class WordAudio {
  WordAudio({
    @visibleForTesting this.base = AppLinks.wordAudioBase,
    @visibleForTesting this.indexFile = wordAudioIndexFile,
  });

  final String base;
  final ModelFile indexFile;

  // Asked once per result in a list, so neither crosses to the platform again.
  late final Future<String> _dir = storageDir();
  bool? _installed;

  WordAudioIndex? _index;
  AudioPlayer? _player;
  final _fetches = <String, Future<WordAudioClip>>{};

  /// Where the word list lives; worked out at runtime and never stored, so it
  /// stays out of the library's re-anchoring.
  static Future<String> storageDir() => noBackupModelDir('word_audio');

  Future<bool> get installed async =>
      _installed ??= await modelFilesInstalled(Directory(await _dir));

  /// The address of a clip. AnkiMobile downloads a field that links to it.
  String clipUrl(String id) => '$base/clips/${id.substring(0, 2)}/$id.mp3';

  Future<void> download({
    void Function(double)? onProgress,
    bool wifiOnly = false,
  }) async {
    final dir = await Directory(await _dir).create(recursive: true);
    await excludeFromIosBackup([dir.path]);
    await downloadModelFiles(
      dir,
      [indexFile],
      onProgress: onProgress,
      wifiOnly: wifiOnly,
    );
    _installed = true;
  }

  /// Deletes the word list and the clips fetched so far.
  Future<void> remove() async {
    _index?.close();
    _index = null;
    _installed = false;
    for (final dir in [await _dir, await _cacheDir()]) {
      if (await Directory(dir).exists()) {
        await Directory(dir).delete(recursive: true);
      }
    }
  }

  /// The clip for a dictionary entry; null when the word list isn't installed
  /// or has no clip for it.
  Future<String?> clipFor(
    String expression,
    String reading, {
    String glossaries = '',
  }) async {
    if (!await installed) return null;
    final path = p.join(await _dir, indexFile.name);
    return (_index ??= WordAudioIndex.open(
      path,
    )).clipFor(expression, reading, glossaries: glossaries);
  }

  /// The clip's file on this device, fetched first if need be. A second call
  /// while fetching (two cards for one word) joins the first.
  ///
  // shortcut: fetched clips are never evicted; 10,000 words is about 86 MB in
  // a folder the OS can clear. Add a size limit if that becomes a complaint.
  Future<WordAudioClip> clipFile(String id) =>
      _fetches[id] ??= _fetch(id).whenComplete(() {
        // A block: returning the removed future would make it wait for itself.
        _fetches.remove(id);
      });

  Future<WordAudioClip> _fetch(String id) async {
    final path = p.join(await _cacheDir(), id.substring(0, 2), '$id.mp3');
    if (await File(path).exists()) return (path: path, source: 'cache');
    await Directory(p.dirname(path)).create(recursive: true);
    // A half-written file under the final name could play.
    final partial = '$path.part';
    await downloadToFile(clipUrl(id), partial);
    await File(partial).rename(path);
    return (path: path, source: 'network');
  }

  /// Plays the clip, stopping any that is still playing. Throws
  /// [WordAudioPlaybackException] when the player refuses the file, which then
  /// goes, so the next try fetches it again.
  Future<void> play(String id) async {
    final clip = await clipFile(id);
    try {
      final player = _player ??= await _newPlayer();
      await player.stop();
      await player.play(DeviceFileSource(clip.path));
    } catch (e) {
      logFailure('word_audio.playback_failed', e);
      await File(clip.path).delete();
      throw const WordAudioPlaybackException();
    }
    logUsage('word_audio.played', attrs: {'source': clip.source});
  }

  /// The user tapped a speaker: other audio only dips, and iOS's silent switch
  /// doesn't mute it.
  static Future<AudioPlayer> _newPlayer() async {
    final player = AudioPlayer();
    await player.setAudioContext(
      AudioContextConfig(focus: AudioContextConfigFocus.duckOthers).build(),
    );
    return player;
  }

  static Future<String> _cacheDir() async =>
      p.join((await getApplicationCacheDirectory()).path, 'word_audio');

  void dispose() {
    _index?.close();
    _index = null;
    unawaited(_player?.dispose());
    _player = null;
  }
}
