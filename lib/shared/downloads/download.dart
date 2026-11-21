/// The one runner of the add-on downloads that run in the app. Background
/// jobs (`runWorkerDownload`), server books and free books don't use it yet.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mekuru/core/platform/android_saf_service.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/core/services/background_work.dart';
import 'package:mekuru/core/services/download_to_file.dart';
import 'package:mekuru/features/backup/data/services/full_backup_service.dart'
    show InsufficientSpaceException;
import 'package:mekuru/features/backup/data/services/ios_full_backup.dart';
import 'package:mekuru/features/manga/data/services/model_download.dart';
import 'package:mekuru/features/sync/data/services/server_download_work.dart'
    show downloadResumable;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Every kind [runDownload] runs and the rules it has; a rule a kind lacks is
/// null or false in its row. Every kind also needs a [NetworkConsent] and
/// stops when Wi-Fi drops unless it allows mobile data ([whileOnWifi]), gives
/// up on a connection stalled for 30 s, joins a download of the same
/// [DownloadSpec.id], and checks a part against the size and sha256 it pins.
enum DownloadKind {
  catalogDictionary(
    room: 0,
    resume: false,
    sweep: true,
    ios: BackgroundJobKind.dictionary,
  ),

  /// The JMdict, KANJIDIC and JPDB tiles.
  fixedDictionary(
    room: null,
    resume: false,
    sweep: true,
    ios: BackgroundJobKind.dictionary,
  ),
  kanjiVg(room: null, resume: false, sweep: false, ios: null),
  uniDic(room: null, resume: false, sweep: false, ios: null),
  mangaOcrIos(room: null, resume: true, sweep: false, ios: null),
  ndlTextModel(room: null, resume: true, sweep: false, ios: null),

  /// A language pair of the Standard translation model.
  translationModel(room: null, resume: true, sweep: false, ios: null),
  wordAudioList(room: null, resume: true, sweep: false, ios: null),

  /// Android's is a WorkManager job (`ModelDownloadJob`).
  wordAudioPackIos(
    room: 0,
    resume: true,
    sweep: false,
    ios: BackgroundJobKind.wordAudio,
  );

  const DownloadKind({
    required this.room,
    required this.resume,
    required this.sweep,
    required this.ios,
  });

  /// R4. Bytes that must be free before it starts, on top of
  /// [DownloadSpec.extraBytes] and the parts not on disk yet, else
  /// [InsufficientSpaceException]. Null: not checked.
  final int? room;

  /// R5. A part cut off midway stays as `<name>.part` in [DownloadSpec.dir]
  /// and the next download continues it. False: it goes to the temporary
  /// folder and is deleted when the download ends.
  final bool resume;

  /// R13, for a part not resumed. Its temporary file gets a unique name, and
  /// one a closed app left is deleted after a day. False: one fixed name.
  final bool sweep;

  /// R9, R10. On iOS it goes on after the user leaves the app, as this kind
  /// of [BackgroundWork], which shows its progress; when iOS ends that, it
  /// stops with [DownloadStoppedException]. Null: it stops with the app.
  final BackgroundJobKind? ios;
}

/// One file of a download. A resumed part pins its [bytes] and [sha256].
typedef DownloadPart = ({String name, String url, int? bytes, String? sha256});

class DownloadSpec {
  const DownloadSpec(
    this.kind, {
    required this.id,
    required this.parts,
    this.dir,
    this.extraBytes = 0,
  });

  final DownloadKind kind;

  /// Joins a second [runDownload]; [stopDownload] and iOS work use it too.
  final String id;

  /// One part unless [kind] resumes.
  final List<DownloadPart> parts;

  /// Where a resumed download keeps its parts and [modelInstalledMarker].
  final String? dir;

  /// Room an import or extraction needs, when [kind] checks for room.
  final int extraBytes;
}

/// iOS ended a download's background work, or [stopDownload] stopped it.
class DownloadStoppedException implements Exception {
  const DownloadStoppedException();

  @override
  String toString() => 'The download was stopped';
}

/// Runs [spec] over the network [consent] allows. A resumed download reports
/// each whole percent of its bytes. Any other downloads its part to a
/// temporary file, which [install] gets and which is deleted afterwards, and
/// reports 0, its transfer up to [share], [install]'s reports, then 1.0.
/// A second call while one runs joins it, without progress.
Future<T> runDownload<T>(
  DownloadSpec spec,
  NetworkConsent consent, {
  double share = 1,
  void Function(double fraction)? onProgress,
  Future<T> Function(String path, void Function(double fraction) report)?
  install,
}) {
  if (_runs[spec.id] case final running?) {
    return running.done.then((value) => value as T);
  }
  final run = _runs[spec.id] = _Run();
  final done = _run(spec, consent, run, share, onProgress, install)
      .whenComplete(() {
        _runs.remove(spec.id);
      });
  run.done = done;
  return done;
}

/// Stops the download [id] with [DownloadStoppedException]; a resumed one
/// keeps its partial file. False when none is under way.
bool stopDownload(String id) {
  final run = _runs[id];
  if (run == null || !run.started) return false;
  run.stop();
  return true;
}

final _runs = <String, _Run>{};

class _Run {
  late final Future<Object?> done;

  /// Past the room check, so a stop now ends it.
  var started = false;
  var stopped = false;
  HttpClient? client;

  void stop() {
    stopped = true;
    client?.close(force: true);
  }
}

Future<T> _run<T>(
  DownloadSpec spec,
  NetworkConsent consent,
  _Run run,
  double share,
  void Function(double)? onProgress,
  Future<T> Function(String, void Function(double))? install,
) async {
  if (spec.kind.room case final room?) await _checkRoom(spec, room);
  run.started = true;
  if (spec.kind.ios case final ios?) {
    BackgroundWork.instance.start(spec.id, ios, onStopped: run.stop);
  }
  void progress(double fraction) {
    BackgroundWork.instance.progress(spec.id, fraction);
    onProgress?.call(fraction);
  }

  try {
    if (spec.kind.resume) {
      await _toFolder(spec, consent, run, progress);
      return null as T;
    }
    // Also inside [install], whose work then rolls back.
    void report(double fraction) {
      if (run.stopped) throw const DownloadStoppedException();
      progress(fraction);
    }

    report(0);
    final result = await _toTemp(spec, consent, run, share, report, install!);
    progress(1);
    return result;
  } catch (_) {
    if (run.stopped) throw const DownloadStoppedException();
    rethrow;
  } finally {
    BackgroundWork.instance.finish(spec.id);
  }
}

Future<void> _checkRoom(DownloadSpec spec, int room) async {
  var needed = room + spec.extraBytes;
  for (final part in spec.parts) {
    needed += part.bytes ?? 0;
    if (spec.kind.resume) {
      final partial = File(p.join(spec.dir!, '${part.name}.part'));
      if (await partial.exists()) needed -= await partial.length();
    }
  }
  int? free;
  try {
    free = defaultTargetPlatform == TargetPlatform.iOS
        ? await IosFullBackup.freeBytes()
        : await AndroidSafService.getFreeBytes(
            (await getApplicationSupportDirectory()).path,
          );
  } catch (_) {
    // Unknown: whatever runs out of room fails loudly instead.
  }
  if (free != null && free < needed) {
    throw InsufficientSpaceException(neededBytes: needed - free);
  }
}

Future<void> _toFolder(
  DownloadSpec spec,
  NetworkConsent consent,
  _Run run,
  void Function(double) progress,
) async {
  final total = spec.parts.fold<int>(0, (sum, part) => sum + part.bytes!);
  var done = 0;
  // Once per whole percent: a socket chunk is far smaller than a listener
  // can show.
  var lastPercent = -1;
  void report(int bytes) {
    final percent = bytes * 100 ~/ total;
    if (percent == lastPercent) return;
    lastPercent = percent;
    progress(bytes / total);
  }

  for (final part in spec.parts) {
    final target = File(p.join(spec.dir!, part.name));
    if (!await _matches(target, part)) {
      final partial = File('${target.path}.part');
      await _transfer(
        run,
        consent,
        (client) => downloadResumable(
          part.url,
          partial.path,
          client: client,
          // GitHub gzips text files: the body would then outgrow its
          // Content-Length once unzipped, and a byte range would count
          // compressed bytes. The pinned sizes and hashes are of the file.
          headers: const {HttpHeaders.acceptEncodingHeader: 'identity'},
          onProgress: (received, _) => report(done + received),
        ),
      );
      if (!await _matches(partial, part)) {
        await partial.delete();
        throw const ModelVerificationException();
      }
      await partial.rename(target.path);
    }
    done += part.bytes!;
    report(done);
  }
  await File(p.join(spec.dir!, modelInstalledMarker)).writeAsString('ok');
}

Future<bool> _matches(File file, DownloadPart part) async {
  if (!await file.exists() || await file.length() != part.bytes) return false;
  return await fileSha256(file.path) == part.sha256;
}

Future<T> _toTemp<T>(
  DownloadSpec spec,
  NetworkConsent consent,
  _Run run,
  double share,
  void Function(double) report,
  Future<T> Function(String, void Function(double)) install,
) async {
  final part = spec.parts.single;
  final temp = await getTemporaryDirectory();
  if (spec.kind.sweep) await _sweep(temp);
  final path = p.join(
    temp.path,
    spec.kind.sweep
        ? 'download_${DateTime.now().microsecondsSinceEpoch}_${part.name}'
        : part.name,
  );
  try {
    await _transfer(
      run,
      consent,
      (client) => downloadToFile(
        part.url,
        path,
        client: client,
        onProgress: (fraction) => report(fraction * share),
      ),
    );
    report(share);
    return await install(path, report);
  } finally {
    try {
      await File(path).delete();
    } on FileSystemException {
      // Already gone (failed download) or undeletable; nothing to leak.
    }
  }
}

/// [fetch] on a client of its own, which a stop closes, and only on Wi-Fi
/// unless [consent] allows mobile data.
Future<void> _transfer(
  _Run run,
  NetworkConsent consent,
  Future<void> Function(HttpClient client) fetch,
) async {
  if (run.stopped) throw const DownloadStoppedException();
  final client = run.client = HttpClient();
  try {
    await (consent.allowsMobileData
        ? fetch(client)
        : whileOnWifi(client, () => fetch(client)));
  } finally {
    run.client = null;
    client.close(force: true);
  }
}

/// A file a closed app left: no running download is a day old.
Future<void> _sweep(Directory dir) async {
  final cutoff = DateTime.now().subtract(const Duration(days: 1));
  try {
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is File &&
          RegExp(r'^download_\d+_').hasMatch(p.basename(entity.path)) &&
          (await entity.lastModified()).isBefore(cutoff)) {
        await entity.delete();
      }
    }
  } on FileSystemException {
    // Best effort: the system clears this directory as well.
  }
}
