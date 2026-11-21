import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/features/settings/data/services/enhanced_furigana_dict_download_service.dart';
import 'package:mekuru/features/settings/presentation/providers/enhanced_furigana_dict_providers.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/shared/utils/format_bytes.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../../../../shared/fake_download_notifiers.dart' show mockWifiConnected;
import '../../../../shared/fake_path_provider.dart';
import '../../../../shared/loopback_http.dart';

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
    // 7e changes this (bug 7): English, with the raw exception and URL.
    expect(
      tile().error,
      'Download failed: HttpException: Download failed: HTTP 404, '
      'uri = https://$url',
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
    // 7e changes this (bug 7): English, with the raw exception.
    expect(
      tile().error,
      startsWith(
        'Download failed: FormatException: Downloaded unidic-lite hash '
        'mismatch',
      ),
    );
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
    expect(tile().error, startsWith('Download failed: '));
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
    expect(
      tile().error,
      'The download stopped because Wi-Fi disconnected. Tap Download to try '
      'again.',
    );
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
    // The catalog's message, in the app's language (English here): the
    // archive, its tar and the files taken out of it, 568.7 MB at once.
    expect(
      tile().error,
      lookupAppLocalizations(
        const Locale('en'),
      ).backupFullNotEnoughSpace(size: formatBytes(568_674_867 - 1000)),
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
}
