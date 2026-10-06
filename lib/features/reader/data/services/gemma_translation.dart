import 'dart:async';
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
import 'package:mekuru/features/sync/data/services/server_download_work.dart'
    show downloadResumable;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Google's Gemma 4 E2B for LiteRT-LM (litert-community, Apache-2.0), pinned
/// to a commit. Values from Step 0 (example/translation_bakeoff/litertlm/meta.json).
const gemmaModelFile = (
  name: 'gemma-4-E2B-it.litertlm',
  url:
      'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/b3ca0d2f076785a8f4b2219ddbd2bdb99954eae1/gemma-4-E2B-it.litertlm',
  bytes: 2588147712,
  sha256: '181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c',
);

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
  HttpClient? _downloadClient;
  // From the start of a download until its transfer ends (not verification).
  bool _preparing = false;
  bool _cancelBeforeFetch = false;

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

  /// Resumable, sha256-verified. Without room for the rest of the model and
  /// its weight cache it fails first with [InsufficientSpaceException]. A
  /// download that starts on Wi-Fi stops with [WifiLostException] when Wi-Fi
  /// goes.
  Future<void> downloadModel({
    void Function(double fraction)? onProgress,
  }) async {
    _preparing = true;
    _cancelBeforeFetch = false;
    try {
      await _downloadModel(onProgress);
    } finally {
      _preparing = false;
    }
  }

  Future<void> _downloadModel(
    void Function(double fraction)? onProgress,
  ) async {
    final dir = await (await _dir).create(recursive: true);
    final destination = File(p.join(dir.path, gemmaModelFile.name));
    final partial = '${destination.path}.part';
    final have = await File(partial).exists()
        ? await File(partial).length()
        : 0;
    final needed = gemmaModelFile.bytes - have + _weightCacheBytes;
    final free = await AndroidSafService.getFreeBytes(dir.path);
    if (free != null && free < needed) {
      throw InsufficientSpaceException(neededBytes: needed - free);
    }
    if (have == gemmaModelFile.bytes) {
      // Complete, but the app died while checking it: check it again.
      onProgress?.call(1);
    } else {
      final wifiOnly = await isOnWifi();
      // Cancelled before there was a connection to close.
      if (_cancelBeforeFetch) throw const HttpException('Download cancelled');
      final client = _downloadClient = HttpClient();
      Future<void> fetch() => downloadResumable(
        gemmaModelFile.url,
        partial,
        client: client,
        onProgress: (received, _) =>
            onProgress?.call(received / gemmaModelFile.bytes),
      );
      try {
        await (wifiOnly ? whileOnWifi(client, fetch) : fetch());
      } finally {
        _downloadClient = null;
        client.close(force: true);
      }
    }
    _preparing = false;
    if (_cancelBeforeFetch) throw const HttpException('Download cancelled');
    if (await _sha256Of(partial) != gemmaModelFile.sha256) {
      await File(partial).delete();
      throw const FileSystemException('Model file failed verification');
    }
    await File(partial).rename(destination.path);
    await File(p.join(dir.path, _marker)).writeAsString('ok');
  }

  /// Stops a running [downloadModel], which then throws. The partial file
  /// stays, so the next download resumes from it. False when there was
  /// nothing to stop (no download, or the file is being verified).
  bool cancelDownload() {
    final client = _downloadClient;
    if (client != null) {
      client.close(force: true);
      return true;
    }
    // Still preparing (folder, space, Wi-Fi): stop before connecting.
    if (_preparing) _cancelBeforeFetch = true;
    return _preparing;
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

  /// Closes the engine and removes the model.
  Future<void> delete() async {
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

// A function of its own, so the isolate takes nothing along but [path]: a
// closure sent to an isolate carries everything its function's closures
// capture (in downloadModel that includes onProgress and, through it, the
// Riverpod notifier, which can't be sent).
Future<String> _sha256Of(String path) => Isolate.run(
  () async => (await sha256.bind(File(path).openRead()).first).toString(),
);
