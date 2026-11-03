import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mekuru/core/config/app_links.dart';
import 'package:mekuru/core/platform/ios_storage.dart';
import 'package:mekuru/core/services/background_work.dart';
import 'package:mekuru/features/backup/data/services/full_backup_service.dart'
    show InsufficientSpaceException;
import 'package:mekuru/features/backup/data/services/ios_full_backup.dart';
import 'package:mekuru/features/manga/data/services/model_download.dart';
import 'package:mekuru/features/manga/data/services/model_download_job.dart';
import 'package:mekuru/features/sync/data/services/server_download_work.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// Every clip in one sqlite file, `clip(id, mp3)`, pinned by size and sha256.
/// One file instead of 248,000 keeps install, delete and storage sane.
const ModelFile wordAudioPackFile = (
  name: 'word_audio_pack_2026-07-27.sqlite',
  url: '${AppLinks.wordAudioBase}/word_audio_pack_2026-07-27.sqlite',
  bytes: 2338205696,
  sha256: 'a7e41c411e683bad67d49c7eb9468c45f596688cc49b0b8c15e34c32d1390bbd',
);

/// WorkManager task name of the pack's download (Android), run by
/// [runWordAudioPackWork].
const wordAudioPackTaskName = 'mekuru.word_audio_pack_download';

const _workName = 'word_audio_pack_download';
const _backgroundWorkId = 'word_audio_pack';

/// The optional offline pack: its download, removal and the clips in it.
class WordAudioPack {
  WordAudioPack({@visibleForTesting this.file = wordAudioPackFile});

  final ModelFile file;

  late final _job = ModelDownloadJob(
    file: file,
    workName: _workName,
    taskName: wordAudioPackTaskName,
    dir: () async => Directory(await _dir),
  );

  late final Future<String> _dir = storageDir();

  /// The transfer running in the app on iOS, closed to stop it.
  HttpClient? _transfer;
  Database? _db;

  /// Not under the word list's folder: each has its own installed marker.
  static Future<String> storageDir() => noBackupModelDir('word_audio_pack');

  /// The download size for display, e.g. "2.3 GB".
  String get downloadSize => '${(file.bytes / 1e9).toStringAsFixed(1)} GB';

  Future<bool> get installed async =>
      modelFilesInstalled(Directory(await _dir));

  /// Whether the folder holds anything, a partial download included.
  Future<bool> hasFiles() async {
    final dir = Directory(await _dir);
    return await dir.exists() && !await dir.list().isEmpty;
  }

  /// Downloads the pack, following it until it is installed: a WorkManager job
  /// on Android, which also goes on after Mekuru closes, and in the app on iOS,
  /// which goes on after Mekuru is left ([BackgroundWork]). Mobile data only
  /// when [mobileData] says the user agreed to it. A stopped download keeps its
  /// partial file, and the next one resumes it.
  Future<void> download({
    void Function(double fraction)? onProgress,
    bool mobileData = false,
  }) => defaultTargetPlatform == TargetPlatform.iOS
      ? _downloadInApp(onProgress, mobileData)
      : _job.run(onProgress: onProgress, mobileData: mobileData);

  Future<void> _downloadInApp(
    void Function(double)? onProgress,
    bool mobileData,
  ) async {
    final dir = await Directory(await _dir).create(recursive: true);
    await excludeFromIosBackup([dir.path]);
    final partial = File(p.join(dir.path, '${file.name}.part'));
    final needed =
        file.bytes - (await partial.exists() ? await partial.length() : 0);
    final free = await IosFullBackup.freeBytes();
    if (free != null && free < needed) {
      throw InsufficientSpaceException(neededBytes: needed - free);
    }
    final client = _transfer = HttpClient();
    var stopped = false;
    BackgroundWork.instance.start(
      _backgroundWorkId,
      BackgroundJobKind.wordAudio,
      onStopped: () {
        stopped = true;
        client.close(force: true);
      },
    );
    try {
      await downloadModelFiles(
        dir,
        [file],
        client: client,
        wifiOnly: !mobileData,
        onProgress: (fraction) {
          onProgress?.call(fraction);
          BackgroundWork.instance.progress(_backgroundWorkId, fraction);
        },
      );
    } catch (_) {
      if (!stopped) rethrow;
      throw const ServerDownloadFailedException(serverDownloadStoppedError);
    } finally {
      BackgroundWork.instance.finish(_backgroundWorkId);
      _transfer = null;
    }
  }

  /// Stops the download; the next [download] resumes it. True when something
  /// was asked to stop, so the error that follows is this.
  bool cancel() {
    if (defaultTargetPlatform != TargetPlatform.iOS) return _job.cancel();
    final client = _transfer;
    client?.close(force: true);
    return client != null;
  }

  /// A job queued, running or finished unseen. iOS writes no job status: its
  /// transfer dies with the app, so there is never anything to follow.
  Future<bool> pending() => _job.pending();

  /// The clip's MP3 from the pack, or null when the pack isn't installed.
  Future<List<int>?> clip(List<int> id) async {
    if (!await installed) return null;
    final path = p.join(await _dir, file.name);
    final rows = (_db ??= sqlite3.open(
      path,
      mode: OpenMode.readOnly,
    )).select('SELECT mp3 FROM clip WHERE id = ?', [id]);
    return rows.isEmpty ? null : rows.first['mp3'] as List<int>;
  }

  /// Deletes the pack, a partial download included.
  Future<void> delete() async {
    close();
    await _job.cancelJob();
    final dir = Directory(await _dir);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  void close() {
    _db?.close();
    _db = null;
  }
}

/// The pack's worker: [runModelDownloadWork] for the pack.
Future<bool> runWordAudioPackWork(
  Map<String, dynamic> input, {
  @visibleForTesting ModelFile file = wordAudioPackFile,
}) => runModelDownloadWork(
  input,
  file: file,
  failedEvent: 'word_audio.pack_download_failed',
  notifyFailed: () => notifyModelDownloadFailed(
    id: 4128,
    failedEvent: 'word_audio.pack_notify_failed',
    title: (l10n) => l10n.wordAudioPackFailedTitle,
    // "Try again from Downloads in Mekuru."
    text: (l10n) => l10n.translationHighQualityDownloadFailedBody,
  ),
);
