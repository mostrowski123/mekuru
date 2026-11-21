import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/settings/presentation/providers/kanjivg_providers.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../../../../shared/fake_download_notifiers.dart' show mockWifiConnected;
import '../../../../shared/fake_path_provider.dart';
import '../../../../shared/loopback_http.dart';

/// The KanjiVG tile's whole download, from tap to files on disk, against a
/// loopback server.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const url =
      'github.com/KanjiVG/kanjivg/releases/download/r20250816/'
      'kanjivg-20250816-all.zip';
  late LoopbackHttp http;
  late Directory root;
  late ProviderContainer container;

  final svg = '<svg/>'.codeUnits;
  final zip = ZipEncoder().encode(
    Archive()
      ..addFile(ArchiveFile('kanjivg/kanji/04e00.svg', svg.length, svg))
      ..addFile(ArchiveFile('kanjivg/kanji/04e8c.svg', svg.length, svg)),
  );

  File inRoot(String path) => File(p.join(root.path, path));
  File archive() => inRoot('kanjivg_download.zip');
  File marker() => inRoot(p.join('kanjivg', '.kanjivg_complete'));
  KanjiVgState tile() => container.read(kanjiVgProvider);
  Future<void> download() =>
      container.read(kanjiVgProvider.notifier).download();

  setUpAll(() async => http = await LoopbackHttp.start());
  tearDownAll(() => http.close());

  setUp(() {
    http.reset();
    root = Directory.systemTemp.createTempSync('kanjivg_download_flow_');
    PathProviderPlatform.instance = FakePathProviderPlatform(root.path);
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
    root.deleteSync(recursive: true);
  });

  test('a download fills the stroke folder, and the tile shows the '
      'count', () async {
    http.handler = serve(zip);
    final progress = <double>[];
    container.listen(kanjiVgProvider, (_, next) {
      if (next.isDownloading) progress.add(next.progress);
    });

    await download();

    expect(http.requests, [url]);
    expect(progress.first, 0.0);
    expect(progress, orderedEquals([...progress]..sort()));
    expect(progress, containsAll([0.9, 1.0]));
    expect(tile().isDownloaded, isTrue);
    expect(tile().isDownloading, isFalse);
    expect(tile().fileCount, 2);
    expect(tile().error, isNull);
    // 7e changes this (bug 7): English, not localized.
    expect(tile().successMessage, 'Downloaded 2 kanji stroke order files.');
    expect(inRoot(p.join('kanjivg', '04e00.svg')).existsSync(), isTrue);
    expect(inRoot(p.join('kanjivg', '04e8c.svg')).existsSync(), isTrue);
    expect(marker().existsSync(), isTrue);
    expect(archive().existsSync(), isFalse);

    // What the tile shows at the next launch.
    final relaunched = ProviderContainer();
    addTearDown(relaunched.dispose);
    await relaunched.read(kanjiVgProvider.notifier).checkStatus();
    expect(relaunched.read(kanjiVgProvider).isDownloaded, isTrue);
    expect(relaunched.read(kanjiVgProvider).fileCount, 2);
  });

  test('a failed download says why and leaves nothing installed', () async {
    await download();

    expect(tile().isDownloaded, isFalse);
    expect(tile().isDownloading, isFalse);
    // 7e changes this (bug 7): English, with the raw exception and URL.
    expect(
      tile().error,
      'Download failed: HttpException: Download failed: HTTP 404, '
      'uri = https://$url',
    );
    expect(marker().existsSync(), isFalse);
    expect(archive().existsSync(), isFalse);
    await container.read(kanjiVgProvider.notifier).checkStatus();
    expect(tile().isDownloaded, isFalse);
  });

  test('a transfer cut off midway leaves no partial archive', () async {
    http.handler = cutOff(zip.sublist(0, zip.length ~/ 2), length: zip.length);

    await download();

    expect(tile().isDownloaded, isFalse);
    expect(tile().error, startsWith('Download failed: '));
    expect(archive().existsSync(), isFalse);
    expect(marker().existsSync(), isFalse);
  });

  test('a download started on Wi-Fi keeps going when Wi-Fi drops', () async {
    // 7e changes this (bug 1): KanjiVG never watches the network, so it
    // goes on over mobile data. The pause outlasts the 2 s Wi-Fi poll.
    mockWifiConnected(true);
    http.handler = serveSlowly(zip, const Duration(seconds: 3));

    final done = download();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    mockWifiConnected(false);
    await done;

    expect(tile().isDownloaded, isTrue);
    expect(tile().error, isNull);
    expect(marker().existsSync(), isTrue);
  });
}
