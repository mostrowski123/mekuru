import 'dart:async';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mekuru/core/platform/android_saf_service.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/backup/data/services/full_backup_service.dart'
    show InsufficientSpaceException;
import 'package:mekuru/features/reader/data/services/sentence_translation.dart';
import 'package:mekuru/features/sync/data/services/server_download_work.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

/// Google's Gemma 4 E2B for LiteRT-LM (litert-community, Apache-2.0), pinned
/// to a commit. Values from Step 0 (example/translation_bakeoff/litertlm/meta.json).
const gemmaModelFile = (
  name: 'gemma-4-E2B-it.litertlm',
  url:
      'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/b3ca0d2f076785a8f4b2219ddbd2bdb99954eae1/gemma-4-E2B-it.litertlm',
  bytes: 2588147712,
  sha256: '181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c',
);

/// WorkManager task name of the model download (Android), run by
/// [runGemmaDownloadWork].
const gemmaDownloadTaskName = 'mekuru.gemma_download';

/// WorkManager unique work name (and tag) of the model download.
const gemmaDownloadWorkName = 'gemma_download';

/// Status error of a model file that failed its sha256 check.
const gemmaVerificationError = 'verification';

const _languages = {
  'en': 'English',
  'es': 'Spanish',
  'id': 'Indonesian',
  'zh-Hans': 'Simplified Chinese',
};

/// Android's high-quality engine: Gemma 4 E2B in Google's LiteRT-LM behind
/// `mekuru/gemma` (GemmaBridge.kt). Translates straight into every UI
/// language. Closed after 5 idle minutes to give its memory back.
class GemmaTranslation implements TranslationEngine {
  GemmaTranslation._();
  static final GemmaTranslation instance = GemmaTranslation._();

  /// Whether High quality can run here: Android, as a 64-bit app. LiteRT-LM
  /// ships only arm64-v8a and x86_64 code, so a 32-bit app could download
  /// the model but never load it.
  static bool get supported =>
      defaultTargetPlatform == TargetPlatform.android &&
      !const {Abi.androidArm, Abi.androidIA32}.contains(Abi.current());

  static const _channel = MethodChannel('mekuru/gemma');
  static const _marker = 'INSTALLED';
  static const _idleLifetime = Duration(minutes: 5);

  /// Room LiteRT-LM's weight cache takes next to the model on first load.
  static const _weightCacheBytes = 800 * 1000 * 1000;

  // Not under translation_models/: removing Standard deletes that folder.
  late final Future<Directory> _dir = getApplicationSupportDirectory().then((
    support,
  ) async {
    final dir = Directory(p.join(support.path, 'gemma-4-e2b'));
    // ponytail: pre-release test builds kept the model under
    // translation_models/; moving it saves testers 2.6 GB. Drop after 1.55.
    final old = Directory(
      p.join(support.path, 'translation_models', 'gemma-4-e2b'),
    );
    if (!await dir.exists() && await old.exists()) await old.rename(dir.path);
    return dir;
  });
  String? _loadedPath;
  Timer? _idleTimer;

  /// Bumped by [cancelDownload], so the [downloadModel] it stops throws.
  var _cancels = 0;

  /// The last [cancelDownload]'s work; a new download waits for it.
  var _stopping = Future<void>.value();

  static String downloadSize() =>
      '${(gemmaModelFile.bytes / 1e9).toStringAsFixed(1)} GB';

  @override
  Future<TranslationStatus> status(String target) async {
    try {
      final dir = await _dir;
      return await File(p.join(dir.path, _marker)).exists()
          ? TranslationStatus.installed
          : TranslationStatus.needsDownload;
    } catch (_) {
      return TranslationStatus.needsDownload;
    }
  }

  @override
  Future<void> download(String target) => downloadModel();

  /// Downloads the model as a WorkManager job ([runGemmaDownloadWork]),
  /// which goes on when Mekuru is left or closed, and follows it until the
  /// model is installed; joins the job when it is already queued or running.
  /// Without room for the rest of the model and its weight cache it fails
  /// first with [InsufficientSpaceException]. A download that starts on
  /// Wi-Fi waits while Wi-Fi is gone; off Wi-Fi the user chose mobile data.
  Future<void> downloadModel({
    void Function(double fraction)? onProgress,
    @visibleForTesting Duration every = const Duration(seconds: 1),
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
      await _cancelDownloadJob();
      throw const HttpException('Download cancelled');
    }

    final dir = await (await _dir).create(recursive: true);
    final work = ServerDownloadWorkDir(dir.path);
    final marker = File(p.join(dir.path, _marker));
    if (await marker.exists()) return work.deleteStatus();
    // Already queued or running (Mekuru restarted mid-download): only
    // follow it. Its partial file and status are the job's.
    if (!await _downloadJobScheduled()) {
      final partial = File(p.join(dir.path, '${gemmaModelFile.name}.part'));
      final have = await partial.exists() ? await partial.length() : 0;
      final needed = gemmaModelFile.bytes - have + _weightCacheBytes;
      final free = await AndroidSafService.getFreeBytes(dir.path);
      if (free != null && free < needed) {
        throw InsufficientSpaceException(neededBytes: needed - free);
      }
      final wifiOnly = await isOnWifi();
      await stopIfCancelled();
      await work.writeStatus(
        ServerDownloadWorkStatus(
          state: ServerDownloadWorkState.running,
          received: have,
          total: gemmaModelFile.bytes,
        ),
      );
      await Workmanager().registerOneOffTask(
        gemmaDownloadWorkName,
        gemmaDownloadTaskName,
        inputData: {'dir': dir.path},
        tag: gemmaDownloadWorkName,
        constraints: Constraints(
          networkType: wifiOnly ? NetworkType.unmetered : NetworkType.connected,
        ),
        // Linear: a retry backs off from its own start, and a 2.6 GB
        // download over a slow line may need many. Android stopping the job
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
      final scheduled = poll % 10 != 0 || await _downloadJobScheduled();
      final status = await work.readStatus();
      if (status?.state == ServerDownloadWorkState.done ||
          (!scheduled && await marker.exists())) {
        onProgress?.call(1);
        // Followed to the end, so the next launch doesn't take it for one
        // that finished unseen ([downloadPending]).
        return work.deleteStatus();
      }
      if (status?.state == ServerDownloadWorkState.failed) {
        throw status?.error == gemmaVerificationError
            ? const FileSystemException('Model file failed verification')
            : HttpException(status?.error ?? 'Download failed');
      }
      if (!scheduled) throw const HttpException('Download was interrupted');
      if (status != null) {
        onProgress?.call(status.received / gemmaModelFile.bytes);
      }
      await Future<void>.delayed(every);
    }
  }

  /// Stops [downloadModel], which then throws, and cancels its job. The
  /// partial file stays, so the next download resumes from it.
  bool cancelDownload() {
    _cancels++;
    _stopping = () async {
      await _cancelDownloadJob();
      try {
        // After the cancel: a job that had only just finished leaves no
        // "done" for the next launch to choose High from.
        final work = ServerDownloadWorkDir((await _dir).path);
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

  /// Whether a download job is queued or running, or one finished while
  /// nothing followed it (reported once).
  Future<bool> downloadPending() async {
    try {
      final work = ServerDownloadWorkDir((await _dir).path);
      switch ((await work.readStatus())?.state) {
        case ServerDownloadWorkState.done:
          await work.deleteStatus();
          return true;
        case ServerDownloadWorkState.running:
          // A job is queued only once its status says it runs. Asked only
          // then: WorkManager answers on Android's main thread.
          return await _downloadJobScheduled();
        default:
          return false;
      }
    } catch (_) {
      // No app directory (widget tests).
      return false;
    }
  }

  /// Whether the model folder holds anything, a partial download included.
  Future<bool> hasFiles() async {
    try {
      final dir = await _dir;
      return await dir.exists() && !await dir.list().isEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Stops a download job, closes the engine and removes the model.
  Future<void> delete() async {
    await _cancelDownloadJob();
    await close();
    final dir = await _dir;
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  @override
  Future<String> translate(String text, String target) async => translateWith(
    modelPath: p.join((await _dir).path, gemmaModelFile.name),
    text: text,
    target: target,
  );

  /// [translate] with the model path given, for tests.
  Future<String> translateWith({
    required String modelPath,
    required String text,
    required String target,
  }) async {
    if (_loadedPath != modelPath) {
      // LiteRT-LM's ~750 MB weight cache lives next to the model, so
      // deleting the model deletes it; reloads drop from ~2 s to ~0.2 s.
      final backend = await _channel.invokeMethod<String>('load', {
        'path': modelPath,
        'cacheDir': p.dirname(modelPath),
      });
      if (backend == 'cpu') logUsage('translation.gemma_cpu');
      _loadedPath = modelPath;
    }
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleLifetime, close);
    try {
      final reply = await _channel.invokeMethod<String>('translate', {
        'text': text,
        'language': _languages[target] ?? 'English',
      });
      return (reply ?? '').trim();
    } catch (_) {
      // Native load is a no-op for the live path, so close the broken
      // engine; the next request then really loads it again.
      await close();
      rethrow;
    }
  }

  /// Replaces [close] in tests.
  @visibleForTesting
  static Future<void> Function()? debugClose;

  /// Frees the model's memory (switching back to Standard, idle, delete).
  Future<void> close() async {
    final override = debugClose;
    if (override != null) return override();
    _idleTimer?.cancel();
    _idleTimer = null;
    // Even with nothing loaded yet: a first load may be under way, and
    // natively this runs after it.
    _loadedPath = null;
    try {
      await _channel.invokeMethod<void>('close');
    } on MissingPluginException {
      // Not on Android.
    }
  }
}

Future<void> _cancelDownloadJob() async {
  try {
    await Workmanager().cancelByUniqueName(gemmaDownloadWorkName);
  } catch (_) {
    // No WorkManager (tests).
  }
}

/// Whether the download job is queued or running; false without WorkManager
/// (tests).
Future<bool> _downloadJobScheduled() async {
  try {
    return await Workmanager().isScheduledByUniqueName(gemmaDownloadWorkName);
  } catch (_) {
    return false;
  }
}

/// The WorkManager job behind [GemmaTranslation.downloadModel] (Android).
/// Downloads [file] into the input's `dir`, resuming the partial file,
/// verifies and installs it, and records each step in the folder's status
/// ([ServerDownloadWorkDir]). True when the download is over (installed,
/// failed for good, or cancelled: the folder gone or the status no longer
/// running), false to be retried. Android stops it after 10 minutes and
/// runs it again; it goes on from the partial file.
Future<bool> runGemmaDownloadWork(
  Map<String, dynamic> input, {
  @visibleForTesting
  ({String name, String url, int bytes, String sha256}) file = gemmaModelFile,
}) async {
  final dir = input['dir'] as String;
  final work = ServerDownloadWorkDir(dir);
  final marker = File(p.join(dir, GemmaTranslation._marker));
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
  // check is ever renamed, so it isn't checked again (2.6 GB).
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
    if (await _sha256Of(partPath) != file.sha256) {
      await part.delete();
      await work.writeStatus(running().failedWith(gemmaVerificationError));
      // Seen even when Mekuru is closed.
      logFailure(_downloadFailedEvent, gemmaVerificationError, attrs: _worker);
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
        error: '$e',
      ),
    );
    if (giveUp) logFailure(_downloadFailedEvent, e, attrs: _worker);
    return giveUp;
  } finally {
    client.close(force: true);
  }
}

const _downloadFailedEvent = 'translation.high_quality_download_failed';
const _worker = {'route': 'worker'};

// A function of its own, so the isolate takes nothing along but [path]: a
// closure sent to an isolate carries everything its function's closures
// capture, and a closure in runGemmaDownloadWork could take its HttpClient
// or progress callback along, which can't be sent.
Future<String> _sha256Of(String path) => Isolate.run(
  () async => (await sha256.bind(File(path).openRead()).first).toString(),
);
