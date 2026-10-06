import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:mekuru/core/platform/network_status.dart';
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

  late final Future<Directory> _dir = getApplicationSupportDirectory().then(
    (support) =>
        Directory(p.join(support.path, 'translation_models', 'gemma-4-e2b')),
  );
  String? _loadedPath;
  Timer? _idleTimer;

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

  /// Resumable, sha256-verified. A download that starts on Wi-Fi stops with
  /// [WifiLostException] when Wi-Fi goes.
  Future<void> downloadModel({
    void Function(double fraction)? onProgress,
  }) async {
    final dir = await (await _dir).create(recursive: true);
    final destination = File(p.join(dir.path, gemmaModelFile.name));
    final partial = '${destination.path}.part';
    final wifiOnly = await isOnWifi();
    final client = HttpClient();
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
      client.close(force: true);
    }
    final path = partial;
    final digest = await Isolate.run(
      () async => (await sha256.bind(File(path).openRead()).first).toString(),
    );
    if (digest != gemmaModelFile.sha256) {
      await File(partial).delete();
      throw const FileSystemException('Model file failed verification');
    }
    await File(partial).rename(destination.path);
    await File(p.join(dir.path, _marker)).writeAsString('ok');
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
      await _channel.invokeMethod<void>('load', {
        'path': modelPath,
        'cacheDir': p.dirname(modelPath),
      });
      _loadedPath = modelPath;
    }
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleLifetime, close);
    final reply = await _channel.invokeMethod<String>('translate', {
      'text': text,
      'language': _languages[target] ?? 'English',
    });
    return (reply ?? '').trim();
  }

  /// Frees the model's memory (switching back to Standard, idle, delete).
  Future<void> close() async {
    _idleTimer?.cancel();
    _idleTimer = null;
    if (_loadedPath == null) return;
    _loadedPath = null;
    try {
      await _channel.invokeMethod<void>('close');
    } on MissingPluginException {
      // Not on Android.
    }
  }
}
