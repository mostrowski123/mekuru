import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/features/reader/data/services/sentence_translation.dart';
import 'package:mekuru/features/sync/data/services/server_download_work.dart'
    show downloadResumable;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// One file of a Mozilla translation model.
typedef MozillaModelFile = ({
  String name,
  String url,
  int bytes,
  String sha256,
});

const _cdn =
    'https://firefox-settings-attachments.cdn.mozilla.net/main-workspace/translations-models';

/// Mozilla's Firefox Translations models, the uncompressed copies (Remote
/// Settings `translations-models`) of what Firefox for Android downloads.
/// Japanese only pairs with English, so other targets pivot en→X like
/// Firefox does. The file name's first part is its kind for the engine.
const Map<String, List<MozillaModelFile>> mozillaTranslationModels = {
  'ja-en': [
    (
      name: 'model.jaen.intgemm.alphas.bin',
      url: '$_cdn/2b066368-11b5-4cee-92e8-e6156b334f80.bin',
      bytes: 43977787,
      sha256:
          '3a603e20bfe1be86071913f9e23ab5129075bc0a8490151020ac4821e4f17302',
    ),
    (
      name: 'lex.50.50.jaen.s2t.bin',
      url: '$_cdn/4e6b3270-8a2f-491d-b717-f99749328622.bin',
      bytes: 9348172,
      sha256:
          '525f412f0d210536c2933c78ae395fa0bf2b5ee6cc5dda61ebc2e79410ebaee4',
    ),
    (
      name: 'vocab.jaen.spm',
      url: '$_cdn/6f4898e3-ebaa-4a79-a1af-93a4f65b96fa.spm',
      bytes: 1443222,
      sha256:
          '5cb217758bae05877bb3f0c2f612e4e7c1e4cb03c10db11f4a47098d7ae62919',
    ),
  ],
  'en-es': [
    (
      name: 'model.enes.intgemm.alphas.bin',
      url: '$_cdn/a4ba0e94-16de-4058-9a44-5bbbbb3c8640.bin',
      bytes: 31561787,
      sha256:
          '3b1c399511c01c84c36fae5c0524df44096288efdc8236e182b5c97d7ad2244c',
    ),
    (
      name: 'lex.50.50.enes.s2t.bin',
      url: '$_cdn/1834a61e-0331-4c4a-bbc0-dda02afa8188.bin',
      bytes: 4198436,
      sha256:
          '7d51237c0a07027dcd61643cfbbb0f8c48597d19907ef53d2cae9d6bec2cf25c',
    ),
    (
      name: 'vocab.enes.spm',
      url: '$_cdn/170634fd-511a-4a28-b723-0a1025c67feb.spm',
      bytes: 816054,
      sha256:
          '5ae254fa9b15aa182e70fd2a6186b1333c63a29a48043a9224c6aa4fcac058ad',
    ),
  ],
  'en-id': [
    (
      name: 'model.enid.intgemm.alphas.bin',
      url: '$_cdn/0d494914-73de-49af-804a-a4bd443f0554.bin',
      bytes: 17141051,
      sha256:
          'f81f13eef703a4e0650ffc3138a0f4bab7b6c8bfd173ef1b7bda68d16b8bc7e8',
    ),
    (
      name: 'lex.50.50.enid.s2t.bin',
      url: '$_cdn/a9610c56-2593-4513-b4ac-954276327788.bin',
      bytes: 3515428,
      sha256:
          'd37f72bcab6e7bc52fd223350f95521b5810bb2486a97275f86077988fced3f4',
    ),
    (
      name: 'vocab.enid.spm',
      url: '$_cdn/6c49d51b-167b-4bdc-aab8-2abe32105529.spm',
      bytes: 773211,
      sha256:
          '61bc7db24d3b6de638a02a280580a273fe0c942ecbe8a8204b2f81978211db22',
    ),
  ],
  'en-zh': [
    (
      name: 'model.enzh.intgemm.alphas.bin',
      url: '$_cdn/9b99b1f6-34fc-4515-8a32-41d4f1dca3dd.bin',
      bytes: 43849787,
      sha256:
          'f102e513798f5c5e61621e58b08d1c8aa535189a47befdef5613d5b058983fed',
    ),
    (
      name: 'lex.50.50.enzh.s2t.bin',
      url: '$_cdn/28707551-d7ae-4825-ae68-fc21de670332.bin',
      bytes: 6506248,
      sha256:
          '4a5e5827788060f1d718a8132b69440929387514a045796e9b77f935db68c055',
    ),
    (
      name: 'srcvocab.enzh.spm',
      url: '$_cdn/7aab6b99-b731-44ea-bcf6-11a0f1aebe1f.spm',
      bytes: 806952,
      sha256:
          'bd9b65504acc6d9726dd281f7defc2adb7c2c22d0688fe2f84697de25197c8c5',
    ),
    (
      name: 'trgvocab.enzh.spm',
      url: '$_cdn/fea238ef-fb47-4aaf-b463-5d314a306ee6.spm',
      bytes: 772004,
      sha256:
          'aded6993c36e440284d11cec3f6b8aef9c0e43188a772d80be342a713adf223d',
    ),
  ],
};

/// The model pairs that translate Japanese into [target], in order.
List<String> mozillaPairsFor(String target) => switch (target) {
  'en' => const ['ja-en'],
  'zh-Hans' => const ['ja-en', 'en-zh'],
  _ => ['ja-en', 'en-$target'],
};

/// Android's translation engine: Mozilla's Bergamot (the WebAssembly build
/// Firefox ships, in `assets/translate/`) in a headless WebView. The page
/// and the models load from same-origin `appassets.androidplatform.net`
/// URLs, so the models never cross the JavaScript bridge.
class MozillaTranslation implements TranslationEngine {
  MozillaTranslation._();
  static final MozillaTranslation instance = MozillaTranslation._();

  static const _marker = 'INSTALLED';
  static const _origin = 'https://appassets.androidplatform.net';
  static const _page =
      '$_origin/assets/flutter_assets/assets/translate/engine.html';

  /// The WebView holds a few hundred MB of WebAssembly memory, so it goes
  /// when the reader stops asking; a cold start costs a second or two.
  static const _idleLifetime = Duration(minutes: 5);

  HeadlessInAppWebView? _webView;
  Future<InAppWebViewController>? _engine;
  Timer? _idleTimer;

  late final Future<Directory> _root = getApplicationSupportDirectory().then(
    (support) => Directory(p.join(support.path, 'translation_models')),
  );

  /// What [download] fetches for [target], for the mobile-data question.
  static String downloadSize(String target) {
    final bytes = [
      for (final pair in mozillaPairsFor(target))
        ...mozillaTranslationModels[pair]!,
    ].fold<int>(0, (sum, file) => sum + file.bytes);
    return '${(bytes / 1000000).round()} MB';
  }

  @override
  Future<TranslationStatus> status(String target) async {
    try {
      final root = await _root;
      for (final pair in mozillaPairsFor(target)) {
        if (!await File(p.join(root.path, pair, _marker)).exists()) {
          return TranslationStatus.needsDownload;
        }
      }
      return TranslationStatus.installed;
    } catch (_) {
      // No app directory (a widget test): nothing to translate with.
      return TranslationStatus.unsupported;
    }
  }

  /// Downloads and verifies each pair [target] needs. An interrupted
  /// download keeps its partial file and the next one resumes it. One that
  /// starts on Wi-Fi stops with [WifiLostException] when Wi-Fi goes, rather
  /// than go on over mobile data unasked.
  @override
  Future<void> download(String target) async {
    final wifiOnly = await isOnWifi();
    final root = await _root;
    for (final pair in mozillaPairsFor(target)) {
      final dir = Directory(p.join(root.path, pair));
      final marker = File(p.join(dir.path, _marker));
      if (await marker.exists()) continue;
      await dir.create(recursive: true);
      for (final file in mozillaTranslationModels[pair]!) {
        final destination = File(p.join(dir.path, file.name));
        // Only a verified file is ever renamed into place.
        if (await destination.exists() &&
            await destination.length() == file.bytes) {
          continue;
        }
        final partial = '${destination.path}.part';
        final client = HttpClient();
        Future<void> fetch() =>
            downloadResumable(file.url, partial, client: client);
        try {
          await (wifiOnly ? whileOnWifi(client, fetch) : fetch());
        } finally {
          client.close(force: true);
        }
        if (!await _matches(File(partial), file)) {
          await File(partial).delete();
          throw const FileSystemException('Model file failed verification');
        }
        await File(partial).rename(destination.path);
      }
      await marker.writeAsString('ok');
    }
  }

  /// Removes every downloaded pair, the English pivots included.
  Future<void> delete() async {
    await _stop();
    final root = await _root;
    if (await root.exists()) await root.delete(recursive: true);
  }

  @override
  Future<String> translate(String text, String target) async {
    final controller = await (_engine ??= _start());
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleLifetime, _stop);
    final result = await controller.callAsyncJavaScript(
      functionBody: 'return await mekuruTranslate(text, pairs);',
      arguments: {
        'text': text,
        'pairs': [
          for (final pair in mozillaPairsFor(target))
            {
              'name': pair,
              'files': {
                for (final file in mozillaTranslationModels[pair]!)
                  file.name.split('.').first:
                      '$_origin/models/$pair/${file.name}',
              },
            },
        ],
      },
    );
    final error = result?.error;
    if (result == null || error != null) {
      throw Exception('Translation engine: ${error ?? 'no result'}');
    }
    return result.value as String? ?? '';
  }

  Future<InAppWebViewController> _start() async {
    final loaded = Completer<InAppWebViewController>();
    final webView = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(_page)),
      initialSettings: InAppWebViewSettings(
        webViewAssetLoader: WebViewAssetLoader(
          pathHandlers: [
            AssetsPathHandler(path: '/assets/'),
            _ModelsPathHandler((await _root).path),
          ],
        ),
      ),
      onLoadStop: (controller, _) {
        if (!loaded.isCompleted) loaded.complete(controller);
      },
      onReceivedError: (_, request, error) {
        if (request.isForMainFrame != false && !loaded.isCompleted) {
          loaded.completeError(Exception(error.description));
        }
      },
    );
    _webView = webView;
    try {
      await webView.run();
      return await loaded.future.timeout(const Duration(seconds: 20));
    } catch (_) {
      await _stop();
      rethrow;
    }
  }

  Future<void> _stop() async {
    _idleTimer?.cancel();
    _idleTimer = null;
    _engine = null;
    final webView = _webView;
    _webView = null;
    await webView?.dispose();
  }

  /// Hashed off the UI isolate: the model alone is 44 MB.
  static Future<bool> _matches(File file, MozillaModelFile expected) async {
    if (!await file.exists() || await file.length() != expected.bytes) {
      return false;
    }
    final path = file.path;
    final digest = await Isolate.run(
      () async => (await sha256.bind(File(path).openRead()).first).toString(),
    );
    return digest == expected.sha256;
  }
}

/// Serves the downloaded models at `/models/`. flutter_inappwebview_android
/// 1.1.3's `InternalStoragePathHandler.toMap` calls itself until the stack
/// overflows; the native side reads only these three keys.
class _ModelsPathHandler extends InternalStoragePathHandler {
  _ModelsPathHandler(String directory)
    : super(path: '/models/', directory: directory);

  @override
  Map<String, dynamic> toMap() => {
    'type': type,
    'path': path,
    'directory': directory,
  };
}
