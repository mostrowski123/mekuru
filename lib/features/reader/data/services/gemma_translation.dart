import 'dart:async';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/manga/data/services/model_download.dart'
    show ModelFile, modelInstalledMarker;
import 'package:mekuru/features/manga/data/services/model_download_job.dart';
import 'package:mekuru/features/reader/data/services/sentence_translation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Google's Gemma 4 E2B for LiteRT-LM (litert-community, Apache-2.0), pinned
/// to a commit. Values from Step 0 (example/translation_bakeoff/litertlm/meta.json).
const ModelFile gemmaModelFile = (
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

  /// The model is loading into memory (a first translation, or the first
  /// after an idle close), which can take a while: the Sentence tab says so.
  final loading = ValueNotifier<bool>(false);

  late final _job = ModelDownloadJob(
    file: gemmaModelFile,
    workName: gemmaDownloadWorkName,
    taskName: gemmaDownloadTaskName,
    dir: () => _dir,
    extraBytes: _weightCacheBytes,
  );

  static String downloadSize() =>
      '${(gemmaModelFile.bytes / 1e9).toStringAsFixed(1)} GB';

  @override
  Future<TranslationStatus> status(String target) async {
    try {
      final dir = await _dir;
      return await File(p.join(dir.path, modelInstalledMarker)).exists()
          ? TranslationStatus.installed
          : TranslationStatus.needsDownload;
    } catch (_) {
      return TranslationStatus.needsDownload;
    }
  }

  @override
  Future<void> download(String target) => downloadModel();

  /// Downloads the model as a WorkManager job ([runGemmaDownloadWork]) and
  /// follows it until the model is installed ([ModelDownloadJob.run], which
  /// also says what happens without room or off Wi-Fi).
  Future<void> downloadModel({
    void Function(double fraction)? onProgress,
    bool mobileData = false,
    @visibleForTesting Duration every = const Duration(seconds: 1),
  }) => _job.run(onProgress: onProgress, mobileData: mobileData, every: every);

  /// Stops the download; the next [downloadModel] resumes from its partial
  /// file. Always reports that something was asked to stop.
  bool cancelDownload() => _job.cancel();

  /// Whether a download job is queued or running, or one finished while
  /// nothing followed it (reported once).
  Future<bool> downloadPending() => _job.pending();

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
    await _job.cancelJob();
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
    var tooLate = false;
    if (_loadedPath != modelPath) {
      final waited = Stopwatch()..start();
      loading.value = true;
      try {
        // LiteRT-LM's ~750 MB weight cache lives next to the model, so
        // deleting the model deletes it; reloads drop from ~2 s to ~0.2 s.
        final backend = await _channel.invokeMethod<String>('load', {
          'path': modelPath,
          'cacheDir': p.dirname(modelPath),
        });
        if (backend == 'cpu') logUsage('translation.gemma_cpu');
        _loadedPath = modelPath;
      } finally {
        loading.value = false;
      }
      // Slower than [highQualityTimeout]: the Sentence tab went on with
      // Standard. The model stays loaded for the next sentence, which a
      // translation nobody reads would only hold up.
      tooLate = waited.elapsed >= highQualityTimeout;
    }
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleLifetime, close);
    if (tooLate) {
      throw TimeoutException('Gemma loaded too late', highQualityTimeout);
    }
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

/// The download job's worker: [runModelDownloadWork] for the model.
Future<bool> runGemmaDownloadWork(
  Map<String, dynamic> input, {
  @visibleForTesting ModelFile file = gemmaModelFile,
}) => runModelDownloadWork(
  input,
  file: file,
  failedEvent: _downloadFailedEvent,
  notifyFailed: () => notifyModelDownloadFailed(
    id: _downloadFailedNotification,
    failedEvent: 'translation.high_quality_notify_failed',
    title: (l10n) => l10n.translationHighQualityDownloadFailedTitle,
    text: (l10n) => l10n.translationHighQualityDownloadFailedBody,
  ),
);

const _downloadFailedEvent = 'translation.high_quality_download_failed';

const _downloadFailedNotification = 4127;
