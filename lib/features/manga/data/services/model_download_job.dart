import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:local_manga_ocr/local_manga_ocr.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/backup/data/services/full_backup_service.dart'
    show InsufficientSpaceException;
import 'package:mekuru/features/manga/data/services/model_download.dart';
import 'package:mekuru/features/settings/data/services/app_settings_storage.dart';
import 'package:mekuru/features/sync/data/services/server_download_work.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/shared/downloads/download.dart' show requireRoom;
import 'package:path/path.dart' as p;
import 'package:workmanager/workmanager.dart';

/// Status error of a model file that failed its sha256 check.
const modelJobVerificationError = 'verification';

/// In a [ModelDownloadJob]'s folder while its queued job may use mobile data.
const _mobileDataMarker = 'mobile_data_ok';

/// Why a [ModelDownloadJob]'s percentage stands still, as far as the app can
/// tell; a row shows it in words instead (`jobWaitText`).
enum JobWait {
  /// Nothing known holds it up.
  none,

  /// Off Wi-Fi, and the job may not use mobile data.
  wifi,

  /// No network at all, and the job may use mobile data.
  connection,

  /// Its last attempt failed; WorkManager runs it again after a backoff.
  retry,
}

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
  /// [network] allows it; otherwise it waits for unmetered Wi-Fi, also when it
  /// is queued again for a download already under way. [onProgress] gets the
  /// fraction downloaded and what the job waits for.
  Future<void> run({
    required NetworkConsent network,
    void Function(double fraction, JobWait wait)? onProgress,
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
    // Present while the queued job may use mobile data, so following it
    // after a relaunch knows whether it waits for Wi-Fi.
    final mobileDataOk = File(p.join(folder.path, _mobileDataMarker));
    if (await marker.exists()) return work.deleteStatus();
    // Already queued or running (Mekuru restarted mid-download): only
    // follow it. Its partial file and status are the job's.
    if (!await _scheduled()) {
      final partial = File(p.join(folder.path, '${file.name}.part'));
      final have = await partial.exists() ? await partial.length() : 0;
      await requireRoom(file.bytes - have + extraBytes);
      await stopIfCancelled();
      if (network.allowsMobileData) {
        await mobileDataOk.create();
      } else if (await mobileDataOk.exists()) {
        await mobileDataOk.delete();
      }
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
          networkType: network.allowsMobileData
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
    // A job waits for the network its WorkManager constraint names: Wi-Fi,
    // unless it may use mobile data, then any. It says so, and so does a
    // failed attempt's backoff ([ServerDownloadWorkStatus.failedAttempts]).
    final waitsForWifi = !await mobileDataOk.exists();
    for (var poll = 0; ; poll++) {
      await stopIfCancelled();
      // WorkManager answers on Android's main thread, so it is asked every
      // tenth poll; the status file is read every time. Asked first: once
      // the job is over, its status and marker are final.
      final scheduled = poll % 10 != 0 || await _scheduled();
      final status = await work.readStatus();
      if (status?.state == ServerDownloadWorkState.done ||
          (!scheduled && await marker.exists())) {
        onProgress?.call(1, JobWait.none);
        // Followed to the end, so the next launch doesn't take it for one
        // that finished unseen ([pending]).
        return work.deleteStatus();
      }
      // A cancel while these were read removed the job and marked its
      // status stopped: report the cancel, not what it did.
      await stopIfCancelled();
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
        final wait = waitsForWifi
            ? (await isOnWifi() ? null : JobWait.wifi)
            : (await isConnected() ? null : JobWait.connection);
        onProgress?.call(
          status.received / file.bytes,
          wait ?? (status.failedAttempts > 0 ? JobWait.retry : JobWait.none),
        );
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
  final dir = input['dir'] as String;
  final work = ServerDownloadWorkDir(dir);
  if (!Directory(dir).existsSync() ||
      await File(p.join(dir, modelInstalledMarker)).exists()) {
    return true;
  }
  final previous = await work.readStatus();
  // Never queued, or ended: a stop ([ModelDownloadJob.cancel]) marks it failed.
  if (previous?.state != ServerDownloadWorkState.running) return true;
  return runWorkerDownload(
    work,
    previous: previous,
    name: file.name,
    url: file.url,
    client: HttpClient.new,
    keepsPartOnFullDisk: true,
    bytes: file.bytes,
    verify: (path) async => await fileSha256(path) == file.sha256
        ? null
        : modelJobVerificationError,
    marker: modelInstalledMarker,
    onGiveUp: (error) async {
      // Seen even when Mekuru is closed.
      logFailure(failedEvent, error, attrs: const {'route': 'worker'});
      await notifyFailed();
    },
  );
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
