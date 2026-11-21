import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/core/services/download_to_file.dart';
import 'package:mekuru/features/backup/data/services/full_backup_service.dart'
    show InsufficientSpaceException;
import 'package:mekuru/features/settings/data/services/enhanced_furigana_dict_download_service.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/features/settings/presentation/providers/enhanced_furigana_dict_providers.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/shared/downloads/download.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../../../../shared/fake_download_notifiers.dart';
import '../../../../shared/fake_path_provider.dart';
import '../../../../shared/loopback_http.dart';

/// The real notifier without the status check the screen runs when it opens,
/// whose file check never ends under a widget test's clock.
class _NoStatusCheck extends EnhancedFuriganaDictNotifier {
  @override
  Future<void> checkStatus() async {}
}

/// A download that installs, which no test can serve: the archive's hash is
/// pinned to the published release.
class _Installs extends _NoStatusCheck {
  @override
  Future<void> download(NetworkConsent network) async {
    state = const EnhancedFuriganaDictState(
      isInstalled: true,
      outcome: (action: TileAction.download, error: null),
    );
  }
}

/// The UniDic-lite (enhanced furigana) tile's download against a loopback
/// server. The archive is pinned by sha256 to the published release, so no
/// test can serve one that installs: a successful install is not pinned here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const url =
      'github.com/mostrowski123/mekuru/releases/download/'
      'dict-unidic-lite-2.1.2/unidic-lite-2.1.2.tar.gz';
  late LoopbackHttp http;
  late Directory root;
  late ProviderContainer container;

  final archiveBytes = gzip.encode(List.filled(4096, 7));

  File inRoot(String path) => File(p.join(root.path, path));
  File archive() => inRoot('unidic_lite_download.tar.gz');
  Directory installDir() => Directory(p.join(root.path, 'unidic-lite'));
  EnhancedFuriganaDictState tile() =>
      container.read(enhancedFuriganaDictProvider);

  /// What the last download failed with.
  Object? failure() {
    expect(tile().outcome?.action, TileAction.download);
    return tile().outcome?.error;
  }

  // Unwatched unless a test asks for Wi-Fi only, as a tap on Wi-Fi does.
  Future<void> download([NetworkConsent network = NetworkConsent.mobileData]) =>
      container.read(enhancedFuriganaDictProvider.notifier).download(network);

  /// No archive, extracted tar or dictionary file is left on disk.
  void expectNothingInstalled() {
    expect(archive().existsSync(), isFalse);
    expect(inRoot('unidic_lite_download.tar.gz.tar').existsSync(), isFalse);
    if (installDir().existsSync()) expect(installDir().listSync(), isEmpty);
  }

  setUpAll(() async => http = await LoopbackHttp.start());
  tearDownAll(() => http.close());

  setUp(() {
    http.reset();
    root = Directory.systemTemp.createTempSync('unidic_download_flow_');
    PathProviderPlatform.instance = FakePathProviderPlatform(root.path);
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
    root.deleteSync(recursive: true);
  });

  test('a failed download says why and installs nothing', () async {
    final seen = <EnhancedFuriganaDictState>[];
    container.listen(enhancedFuriganaDictProvider, (_, next) => seen.add(next));

    await download();

    expect(http.requests, [url]);
    expect(seen.first.isDownloading, isTrue);
    expect(seen.first.progress, 0.0);
    expect(tile().isDownloading, isFalse);
    expect(tile().isInstalled, isFalse);
    expect(
      failure(),
      isA<DownloadHttpException>().having((e) => e.statusCode, 'status', 404),
    );
    expectNothingInstalled();
    expect(await EnhancedFuriganaDictDownloadService.isInstalled(), isFalse);
  });

  test('an archive that fails its hash check is removed with its '
      'folder', () async {
    http.handler = serve(archiveBytes);
    final progress = <double>[];
    container.listen(enhancedFuriganaDictProvider, (_, next) {
      if (next.isDownloading) progress.add(next.progress);
    });

    await download();

    // It reached the "Extracting" step.
    expect(progress, contains(0.85));
    expect(tile().isInstalled, isFalse);
    expect(failure(), isA<FormatException>());
    expect(installDir().existsSync(), isFalse);
    expectNothingInstalled();
  });

  test('a transfer cut off midway leaves no partial archive', () async {
    http.handler = cutOff(
      archiveBytes.sublist(0, archiveBytes.length ~/ 2),
      length: archiveBytes.length,
    );

    await download();

    expect(tile().isInstalled, isFalse);
    expect(failure(), isA<HttpException>());
    expectNothingInstalled();
  });

  test('a download started on Wi-Fi stops when Wi-Fi drops, and says '
      'why', () async {
    // The pause outlasts the 2 s Wi-Fi poll.
    mockWifiConnected(true);
    http.handler = serveSlowly(archiveBytes, const Duration(seconds: 3));

    final done = download(NetworkConsent.wifiOnly);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    mockWifiConnected(false);
    await done;

    expect(tile().isInstalled, isFalse);
    expect(failure(), isA<WifiLostException>());
    expectNothingInstalled();
  });

  test('without room for its peak it fetches nothing and says how much more '
      'it needs', () async {
    const saf = MethodChannel('mekuru/android_saf');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      saf,
      (call) async => call.method == 'getFreeBytes' ? 1000 : null,
    );
    addTearDown(() => messenger.setMockMethodCallHandler(saf, null));

    await download();

    expect(http.requests, isEmpty);
    expect(tile().isDownloading, isFalse);
    expect(tile().isInstalled, isFalse);
    // The archive, its tar and the files taken out of it, 568.7 MB at once.
    expect(
      failure(),
      isA<InsufficientSpaceException>().having(
        (e) => e.neededBytes,
        'needed',
        568_674_867 - 1000,
      ),
    );
    expect(root.listSync(recursive: true).whereType<File>(), isEmpty);
  });

  test('an install from an earlier version shows as installed', () async {
    // The marker existing installs and full backups carry.
    installDir().createSync();
    File(
      p.join(installDir().path, '.install_complete'),
    ).writeAsStringSync('{}');

    await container.read(enhancedFuriganaDictProvider.notifier).checkStatus();

    expect(tile().isInstalled, isTrue);
  });

  testWidgets('in Japanese, the Downloads screen says why a download failed, '
      'and that the dictionary was removed', (tester) async {
    final ja = lookupAppLocalizations(const Locale('ja'));
    final screen = ProviderContainer(
      overrides: fakeDownloadNotifierOverrides(
        [],
        enhancedFurigana: _NoStatusCheck.new,
      ),
    );
    addTearDown(screen.dispose);
    await pumpInJapanese(tester, screen);
    final notifier = screen.read(enhancedFuriganaDictProvider.notifier);
    Future<void> shows(Future<void> Function() action, String text) async {
      await tester.runAsync(action);
      await tester.pump();
      expect(find.text(text), findsOneWidget);
      expect(untranslatedDownloadText, findsNothing);
    }

    await shows(
      () => notifier.download(NetworkConsent.mobileData),
      ja.serverBrowseDownloadFailed(error: ja.serverErrorStatus(status: 404)),
    );
    // Not the published archive, so its hash doesn't match.
    http.handler = serve(archiveBytes);
    await shows(
      () => notifier.download(NetworkConsent.mobileData),
      ja.localOcrDownloadDamaged,
    );
    await shows(notifier.uninstall, ja.downloadsEnhancedFuriganaRemoved);
  });

  for (final lowRamMode in [false, true]) {
    testWidgets('in Japanese, an install says to restart the app'
        '${lowRamMode ? ', and to turn off Low RAM mode' : ''}', (
      tester,
    ) async {
      final ja = lookupAppLocalizations(const Locale('ja'));
      final screen = ProviderContainer(
        overrides: [
          lowRamModeProvider.overrideWithBuild((ref, _) => lowRamMode),
          ...fakeDownloadNotifierOverrides([], enhancedFurigana: _Installs.new),
        ],
      );
      addTearDown(screen.dispose);
      await pumpInJapanese(tester, screen);

      await screen
          .read(enhancedFuriganaDictProvider.notifier)
          .download(NetworkConsent.mobileData);
      await tester.pump();

      expect(
        find.text(
          lowRamMode
              ? ja.downloadsEnhancedFuriganaInstalledLowRam
              : ja.downloadsEnhancedFuriganaInstalledRestart,
        ),
        findsOneWidget,
      );
      expect(untranslatedDownloadText, findsNothing);
    });
  }
}
