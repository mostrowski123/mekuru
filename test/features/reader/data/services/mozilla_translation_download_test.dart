import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/features/manga/data/services/model_download.dart';
import 'package:mekuru/features/reader/data/services/mozilla_translation.dart';
import 'package:mekuru/features/reader/data/services/sentence_translation.dart';
import 'package:mekuru/features/sync/data/services/server_download_work.dart'
    show ServerDownloadHttpException;
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../../../../shared/fake_download_notifiers.dart' show mockWifiConnected;
import '../../../../shared/fake_path_provider.dart';
import '../../../../shared/loopback_http.dart';

/// `MozillaTranslation.download`, the Standard translation model, against a
/// loopback server. The models are pinned by sha256 to Mozilla's files, so no
/// test can serve a pair that verifies: a successful install is not pinned
/// here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final engine = MozillaTranslation.instance;
  late LoopbackHttp http;
  late Directory root;

  /// Where the app keeps the pair [pair].
  Directory pairDir(String pair) =>
      Directory(p.join(root.path, 'translation_models', pair));

  /// The first file of [pair], as `host/path`.
  String firstFileOf(String pair) {
    final url = Uri.parse(mozillaTranslationModels[pair]!.first.url);
    return '${url.host}${url.path}';
  }

  File partOf(String pair) => File(
    p.join(
      pairDir(pair).path,
      '${mozillaTranslationModels[pair]!.first.name}.part',
    ),
  );

  void markInstalled(String pair) {
    pairDir(pair).createSync(recursive: true);
    File(
      p.join(pairDir(pair).path, modelInstalledMarker),
    ).writeAsStringSync('ok');
  }

  final firstBytes = mozillaTranslationModels['ja-en']!.first.bytes;

  setUpAll(() async {
    // The engine keeps the first app directory it sees, so one for the file.
    root = Directory.systemTemp.createTempSync('mozilla_download_test_');
    PathProviderPlatform.instance = FakePathProviderPlatform(root.path);
    http = await LoopbackHttp.start();
  });

  tearDownAll(() async {
    await http.close();
    root.deleteSync(recursive: true);
  });

  setUp(() {
    http.reset();
    final models = Directory(p.join(root.path, 'translation_models'));
    if (models.existsSync()) models.deleteSync(recursive: true);
  });

  test('a target whose pairs are installed fetches nothing', () async {
    markInstalled('ja-en');

    await engine.download('en', NetworkConsent.mobileData);

    expect(http.requests, isEmpty);
    expect(await engine.status('en'), TranslationStatus.installed);
    expect(await engine.status('es'), TranslationStatus.needsDownload);
  });

  test('a download fetches only the pairs not installed yet', () async {
    markInstalled('ja-en');

    await expectLater(
      engine.download('es', NetworkConsent.mobileData),
      throwsA(
        isA<ServerDownloadHttpException>().having(
          (e) => e.statusCode,
          'statusCode',
          404,
        ),
      ),
    );

    expect(http.requests, [firstFileOf('en-es')]);
    expect(await engine.status('es'), TranslationStatus.needsDownload);
  });

  test('a cut-off transfer keeps its partial file, reports not installed, '
      'and the next download resumes it', () async {
    http.handler = cutOff(List.filled(1000, 7), length: firstBytes);

    await expectLater(
      engine.download('en', NetworkConsent.mobileData),
      throwsA(isA<HttpException>()),
    );

    expect(await engine.status('en'), TranslationStatus.needsDownload);
    expect(partOf('ja-en').lengthSync(), 1000);
    expect(
      File(p.join(pairDir('ja-en').path, modelInstalledMarker)).existsSync(),
      isFalse,
    );

    http.handler = notFound;
    await expectLater(
      engine.download('en', NetworkConsent.mobileData),
      throwsA(isA<ServerDownloadHttpException>()),
    );
    expect(http.requests, [firstFileOf('ja-en'), firstFileOf('ja-en')]);
    expect(http.ranges, [null, 'bytes=1000-']);
  });

  test('a file that fails verification is deleted, and nothing reports '
      'installed', () async {
    http.handler = serve(List.filled(10, 7));

    await expectLater(
      engine.download('en', NetworkConsent.mobileData),
      throwsA(isA<ModelVerificationException>()),
    );

    expect(await engine.status('en'), TranslationStatus.needsDownload);
    expect(pairDir('ja-en').listSync(), isEmpty);
  });

  test('two downloads of one target at once fetch the file once', () async {
    final release = Completer<void>();
    http.handler = (request) async {
      await release.future;
      await notFound(request);
    };

    final first = engine.download('en', NetworkConsent.mobileData);
    final second = engine.download('en', NetworkConsent.mobileData);
    while (http.requests.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    release.complete();

    await Future.wait([
      for (final download in [first, second])
        expectLater(download, throwsA(isA<ServerDownloadHttpException>())),
    ]);
    expect(http.requests, [firstFileOf('ja-en')]);
  });

  test('a download started on Wi-Fi stops when Wi-Fi goes, keeping its '
      'partial file', () async {
    mockWifiConnected(true);
    http.handler = stall(List.filled(1000, 7), length: firstBytes);

    final download = engine.download('en', NetworkConsent.wifiOnly);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    mockWifiConnected(false);

    await expectLater(download, throwsA(isA<WifiLostException>()));
    expect(partOf('ja-en').lengthSync(), 1000);
    expect(await engine.status('en'), TranslationStatus.needsDownload);
  });
}
