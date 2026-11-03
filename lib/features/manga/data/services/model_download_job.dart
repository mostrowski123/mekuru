import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:local_manga_ocr/local_manga_ocr.dart';
import 'package:mekuru/core/platform/android_saf_service.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/backup/data/services/full_backup_service.dart'
    show InsufficientSpaceException;
import 'package:mekuru/features/manga/data/services/model_download.dart';
import 'package:mekuru/features/settings/data/services/app_settings_storage.dart';
import 'package:mekuru/features/sync/data/services/server_download_work.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:workmanager/workmanager.dart';

/// Status error of a model file that failed its sha256 check.
const modelJobVerificationError = 'verification';

/// One large pinned file downloaded by a WorkManager job on Android
/// ([runModelDownloadWork]), which goes on when Mekuru is left or closed.
/// Plain work, never a foreground service: Play rejected that for OCR.
class ModelDownloadJob {
  ModelDownloadJob({
    required this.file,
    required this.workName,
    required this.taskName,
    required this.dir,
    this.extraBytes = 0,
  });

  final ModelFile file;

  /// WorkManager's unique work name (and tag).
  final String workName;

  /// What `ocrWorkerCallbackDispatcher` routes to [runModelDownloadWork].
  final String taskName;

  /// The folder of the file, its partial file and the job's status.
  final Future<Directory> Function() dir;

  /// Room needed next to the file, on top of the file itself.
  final int extraBytes;

  /// Bumped by [cancel], so the [run] it stops throws.
  var _cancels = 0;

  /// The last [cancel]'s work; a new download waits for it.
  var _stopping = Future<void>.value();

  /// Downloads the file as the job and follows it until the file is
  /// installed; joins the job when it is already queued or running. Without
  /// room for the rest of the file and [extraBytes] it fails first with
  /// [InsufficientSpaceException]. The job uses mobile data only when
  /// [mobileData] says the user agreed to it; otherwise it waits for unmetered
  /// Wi-Fi, also when it is queued again for a download already under way.
  Future<void> run({
    void Function(double fraction)? onProgress,
    bool mobileData = false,
    Duration every = const Duration(seconds: 1),
  }) async {
    // Before any await, so a cancel that comes while an earlier one ends
    // still stops this download.
    final cancels = _cancels;
    await _stopping;
    Future<void> stopIfCancelled() async {
      if (_cancels == cancels) return;
      // Thrown once the job is cancelled, so the next start can't join it.
      await _stopping;
      // Again: the cancel may have come while the job was being queued.
      await cancelJob();
      throw const HttpException('Download cancelled');
    }

    final folder = await (await dir()).create(recursive: true);
    final work = ServerDownloadWorkDir(folder.path);
    final marker = File(p.join(folder.path, modelInstalledMarker));
    if (await marker.exists()) return work.deleteStatus();
    // Already queued or running (Mekuru restarted mid-download): only
    // follow it. Its partial file and status are the job's.
    if (!await _scheduled()) {
      final partial = File(p.join(folder.path, '${file.name}.part'));
      final have = await partial.exists() ? await partial.length() : 0;
      final needed = file.bytes - have + extraBytes;
      final free = await AndroidSafService.getFreeBytes(folder.path);
      if (free != null && free < needed) {
        throw InsufficientSpaceException(neededBytes: needed - free);
      }
      await stopIfCancelled();
      await work.writeStatus(
        ServerDownloadWorkStatus(
          state: ServerDownloadWorkState.running,
          received: have,
          total: file.bytes,
        ),
      );
      await Workmanager().registerOneOffTask(
        workName,
        taskName,
        inputData: {'dir': folder.path},
        tag: workName,
        constraints: Constraints(
          networkType: mobileData
              ? NetworkType.connected
              : NetworkType.unmetered,
        ),
        // Linear: a retry backs off from its own start, and a download of
        // gigabytes over a slow line may need many. Android stopping the job
        // (its 10 minutes are up) runs it again without a new backoff.
        backoffPolicy: BackoffPolicy.linear,
        backoffPolicyDelay: const Duration(seconds: 30),
        // Joins a job queued meanwhile instead of starting it over.
        existingWorkPolicy: ExistingWorkPolicy.keep,
      );
    }
    for (var poll = 0; ; poll++) {
      await stopIfCancelled();
      // WorkManager answers on Android's main thread, so it is asked every
      // tenth poll; the status file is read every time. Asked first: once
      // the job is over, its status and marker are final.
      final scheduled = poll % 10 != 0 || await _scheduled();
      final status = await work.readStatus();
      if (status?.state == ServerDownloadWorkState.done ||
          (!scheduled && await marker.exists())) {
        onProgress?.call(1);
        // Followed to the end, so the next launch doesn't take it for one
        // that finished unseen ([pending]).
        return work.deleteStatus();
      }
      if (status?.state == ServerDownloadWorkState.failed) {
        throw status?.error == modelJobVerificationError
            ? const ModelVerificationException()
            : ServerDownloadFailedException(status?.error ?? '');
      }
      if (!scheduled) {
        throw const ServerDownloadFailedException(
          serverDownloadInterruptedError,
        );
      }
      if (status != null) {
        onProgress?.call(status.received / file.bytes);
      }
      await Future<void>.delayed(every);
    }
  }

  /// Stops the download by cancelling the job; the next [run] resumes from
  /// its partial file. Always reports that something was asked to stop.
  bool cancel() {
    _cancels++;
    _stopping = () async {
      await cancelJob();
      try {
        // After the cancel: a job that had only just finished leaves no
        // "done" for the next launch to act on.
        final work = ServerDownloadWorkDir((await dir()).path);
        final status = await work.readStatus();
        if (status != null) {
          await work.writeStatus(status.failedWith(serverDownloadStoppedError));
        }
      } catch (_) {
        // No folder: nothing was downloading.
      }
    }();
    return true;
  }

  /// Whether the job is queued or running, or one finished while nothing
  /// followed it (reported once).
  Future<bool> pending() async {
    try {
      final work = ServerDownloadWorkDir((await dir()).path);
      switch ((await work.readStatus())?.state) {
        case ServerDownloadWorkState.done:
          await work.deleteStatus();
          return true;
        case ServerDownloadWorkState.running:
          // A job is queued only once its status says it runs. Asked only
          // then: WorkManager answers on Android's main thread.
          return await _scheduled();
        default:
          return false;
      }
    } catch (_) {
      // No app directory (widget tests).
      return false;
    }
  }

  /// Cancels the queued or running job and nothing else.
  Future<void> cancelJob() async {
    try {
      await Workmanager().cancelByUniqueName(workName);
    } catch (_) {
      // No WorkManager (tests).
    }
  }

  /// Asked of WorkManager; false where it isn't available (tests).
  Future<bool> _scheduled() async {
    try {
      return await Workmanager().isScheduledByUniqueName(workName);
    } catch (_) {
      return false;
    }
  }
}

/// The worker of a [ModelDownloadJob]. True when the job is over, false to be
/// retried. A failure goes into the folder's status for the app to read, and
/// a give-up also to telemetry as [failedEvent] and to [notifyFailed], which
/// reaches the user when Mekuru is closed.
Future<bool> runModelDownloadWork(
  Map<String, dynamic> input, {
  required ModelFile file,
  required String failedEvent,
  required Future<void> Function() notifyFailed,
}) async {
  const worker = {'route': 'worker'};
  final dir = input['dir'] as String;
  final work = ServerDownloadWorkDir(dir);
  final marker = File(p.join(dir, modelInstalledMarker));
  if (!Directory(dir).existsSync() || await marker.exists()) return true;
  final previous = await work.readStatus();
  if (previous == null || previous.state != ServerDownloadWorkState.running) {
    return true;
  }
  Future<void> install() async {
    await marker.writeAsString('ok');
    await work.writeStatus(
      ServerDownloadWorkStatus(
        state: ServerDownloadWorkState.done,
        received: file.bytes,
        total: file.bytes,
      ),
    );
  }

  // Stopped between the rename and the marker. Only a file that passed its
  // check is ever renamed, so it isn't checked again (gigabytes).
  final model = File(p.join(dir, file.name));
  if (await model.exists() && await model.length() == file.bytes) {
    await install();
    return true;
  }
  final partPath = p.join(dir, '${file.name}.part');
  final part = File(partPath);
  final startBytes = await part.exists() ? await part.length() : 0;
  var received = startBytes;
  ServerDownloadWorkStatus running() => ServerDownloadWorkStatus(
    state: ServerDownloadWorkState.running,
    received: received,
    total: file.bytes,
  );
  var lastWrite = DateTime.fromMillisecondsSinceEpoch(0);
  // Progress writes queue up here, so a late one can't land after (and
  // overwrite) the final status.
  var writes = Future<void>.value();
  final client = HttpClient();
  try {
    // A complete file whose check was cut short is only checked again.
    if (startBytes != file.bytes) {
      await downloadResumable(
        file.url,
        partPath,
        client: client,
        onProgress: (bytes, _) {
          received = bytes;
          final now = DateTime.now();
          if (now.difference(lastWrite) < const Duration(milliseconds: 500)) {
            return;
          }
          lastWrite = now;
          final status = running();
          writes = writes
              .then((_) => work.writeStatus(status))
              .catchError((_) {});
        },
      );
      await writes;
      // All there: the app shows it being checked.
      await work.writeStatus(running());
    }
    if (await fileSha256(partPath) != file.sha256) {
      await part.delete();
      await work.writeStatus(running().failedWith(modelJobVerificationError));
      // Seen even when Mekuru is closed.
      logFailure(failedEvent, modelJobVerificationError, attrs: worker);
      await notifyFailed();
      return true;
    }
    await part.rename(model.path);
    await install();
    return true;
  } catch (e) {
    await writes;
    if (!Directory(dir).existsSync()) return true;
    final failedAttempts = received > startBytes
        ? 1
        : previous.failedAttempts + 1;
    final giveUp =
        (e is ServerDownloadHttpException && e.isPermanent) ||
        failedAttempts >= serverDownloadMaxFailedAttempts;
    await work.writeStatus(
      ServerDownloadWorkStatus(
        state: giveUp
            ? ServerDownloadWorkState.failed
            : ServerDownloadWorkState.running,
        received: received,
        total: file.bytes,
        failedAttempts: failedAttempts,
        error: serverDownloadErrorCode(e),
      ),
    );
    if (giveUp) {
      logFailure(failedEvent, e, attrs: worker);
      await notifyFailed();
    }
    return giveUp;
  } finally {
    client.close(force: true);
  }
}

/// Tells the user a [ModelDownloadJob] gave up, when Mekuru is out of sight (on
/// screen, Downloads shows it), in the app's language: the worker has no
/// widget tree to take it from.
Future<void> notifyModelDownloadFailed({
  required int id,
  required String failedEvent,
  required String Function(AppLocalizations) title,
  required String Function(AppLocalizations) text,
}) async {
  try {
    final language =
        await SharedPreferencesAppSettingsStorage().loadAppLanguage() ??
        AppLanguage.system;
    final l10n = lookupAppLocalizations(
      resolveSupportedAppLocale(
        appLanguageLocaleOverride(language) ??
            PlatformDispatcher.instance.locale,
        AppLocalizations.supportedLocales,
      ),
    );
    await LocalMangaOcr.postNotification(
      id: id,
      channelId: 'downloads',
      channelName: l10n.downloadsTitle,
      title: title(l10n),
      text: text(l10n),
    );
  } catch (e) {
    logFailure(failedEvent, e, attrs: const {'route': 'worker'});
  }
}
