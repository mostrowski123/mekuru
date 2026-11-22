import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/core/services/download_to_file.dart';
import 'package:mekuru/features/backup/data/services/full_backup_service.dart'
    show InsufficientSpaceException;
import 'package:mekuru/features/settings/presentation/providers/kanjivg_providers.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/shared/downloads/download.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../../../../shared/fake_download_notifiers.dart';
import '../../../../shared/fake_path_provider.dart';
import '../../../../shared/free_space_fakes.dart';
import '../../../../shared/loopback_http.dart';

/// The real notifier without the status check the screen runs when it opens,
/// whose file check never ends under a widget test's clock.
class _NoStatusCheck extends KanjiVgNotifier {
  @override
  Future<void> checkStatus() async {}
}

/// [zip] with the deflated data of its entry [name] overwritten, so the
/// entries before it extract and that one fails to inflate.
List<int> _damageEntry(List<int> zip, String name) {
  final bytes = Uint8List.fromList(zip);
  final view = ByteData.sublistView(bytes);
  for (var at = 0; at + 30 < bytes.length; at++) {
    if (view.getUint32(at, Endian.little) != 0x04034b50) continue;
    final nameLength = view.getUint16(at + 26, Endian.little);
    final start = at + 30;
    if (String.fromCharCodes(bytes, start, start + nameLength) != name) {
      continue;
    }
    // 8: deflated. A stored entry would extract whatever its bytes are.
    expect(view.getUint16(at + 8, Endian.little), 8);
    final data = start + nameLength + view.getUint16(at + 28, Endian.little);
    bytes.fillRange(data, data + 8, 0xff);
    return bytes;
  }
  throw StateError('No entry $name');
}

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

  /// What the last download failed with.
  Object? failure() {
    expect(tile().outcome?.action, TileAction.download);
    return tile().outcome?.error;
  }

  // Unwatched unless a test asks for Wi-Fi only, as a tap on Wi-Fi does.
  Future<void> download([NetworkConsent network = NetworkConsent.mobileData]) =>
      container.read(kanjiVgProvider.notifier).download(network);

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
    expect(tile().outcome, (action: TileAction.download, error: null));
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
    expect(
      failure(),
      isA<DownloadHttpException>().having((e) => e.statusCode, 'status', 404),
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
    expect(failure(), isA<HttpException>());
    expect(archive().existsSync(), isFalse);
    expect(marker().existsSync(), isFalse);
  });

  test('an error page in place of the zip fails as damaged and installs '
      'nothing', () async {
    // A captive portal or a proxy answers 200 with its own page.
    http.handler = serve('<html><body>Sign in</body></html>'.codeUnits);

    await download();

    // Was: downloaded, 0 files, and the installed marker written.
    expect(tile().isDownloaded, isFalse);
    expect(failure(), isA<FormatException>());
    expect(marker().existsSync(), isFalse);
    expect(root.listSync(recursive: true).whereType<File>(), isEmpty);
    await container.read(kanjiVgProvider.notifier).checkStatus();
    expect(tile().isDownloaded, isFalse);
  });

  test('an archive that breaks partway through its SVGs leaves none of '
      'them', () async {
    // Long enough to be deflated, so a damaged entry fails to inflate.
    final big = ('<svg>${'x' * 2000}</svg>').codeUnits;
    final whole = ZipEncoder().encode(
      Archive()
        ..addFile(ArchiveFile('kanjivg/kanji/04e00.svg', big.length, big))
        ..addFile(ArchiveFile('kanjivg/kanji/04e8c.svg', big.length, big)),
    );
    http.handler = serve(_damageEntry(whole, 'kanjivg/kanji/04e8c.svg'));

    await download();

    expect(tile().isDownloaded, isFalse);
    expect(failure(), isA<FormatException>());
    // Was: 04e00.svg left in the folder, without the marker.
    expect(root.listSync(recursive: true).whereType<File>(), isEmpty);
    await container.read(kanjiVgProvider.notifier).checkStatus();
    expect(tile().isDownloaded, isFalse);
  });

  test('an install already there survives a download that breaks partway, '
      'unchanged', () async {
    final old = inRoot(p.join('kanjivg', '04e00.svg'))
      ..createSync(recursive: true)
      ..writeAsStringSync('OLD');
    marker().writeAsStringSync('KanjiVG\n');
    final big = ('<svg>${'x' * 2000}</svg>').codeUnits;
    final whole = ZipEncoder().encode(
      Archive()
        ..addFile(ArchiveFile('kanjivg/kanji/04e00.svg', big.length, big))
        ..addFile(ArchiveFile('kanjivg/kanji/04e8c.svg', big.length, big)),
    );
    http.handler = serve(_damageEntry(whole, 'kanjivg/kanji/04e8c.svg'));

    await download();

    expect(failure(), isA<FormatException>());
    expect(marker().existsSync(), isTrue);
    // Was: 04e00.svg rewritten from the broken download.
    expect(old.readAsStringSync(), 'OLD');
    expect(
      root.listSync(recursive: true).whereType<File>().map((f) => f.path),
      unorderedEquals([old.path, marker().path]),
    );
  });

  test('without room for the zip and its SVGs it fetches nothing and says '
      'how much more it needs', () async {
    mockFreeBytes(1000);
    http.handler = serve(zip);

    await download();

    expect(http.requests, isEmpty);
    expect(tile().isDownloading, isFalse);
    expect(tile().isDownloaded, isFalse);
    expect(
      failure(),
      isA<InsufficientSpaceException>().having(
        (e) => e.neededBytes,
        'needed',
        102_568_762 - 1000,
      ),
    );
    expect(root.listSync(recursive: true).whereType<File>(), isEmpty);
  });

  test('a download started on Wi-Fi stops when Wi-Fi drops, and says '
      'why', () async {
    // The pause outlasts the 2 s Wi-Fi poll.
    mockWifiConnected(true);
    http.handler = serveSlowly(zip, const Duration(seconds: 3));

    final done = download(NetworkConsent.wifiOnly);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    mockWifiConnected(false);
    await done;

    expect(tile().isDownloaded, isFalse);
    expect(failure(), isA<WifiLostException>());
    expect(marker().existsSync(), isFalse);
    expect(archive().existsSync(), isFalse);
  });

  testWidgets('in Japanese, the Downloads screen says why a download failed, '
      'then that it downloaded, then that it was deleted', (tester) async {
    final ja = lookupAppLocalizations(const Locale('ja'));
    final screen = ProviderContainer(
      overrides: fakeDownloadNotifierOverrides([], kanjiVg: _NoStatusCheck.new),
    );
    addTearDown(screen.dispose);
    await pumpInJapanese(tester, screen);
    final notifier = screen.read(kanjiVgProvider.notifier);
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
    http.handler = serve('<html>Sign in</html>'.codeUnits);
    await shows(
      () => notifier.download(NetworkConsent.mobileData),
      ja.localOcrDownloadDamaged,
    );
    http.handler = serve(zip);
    await shows(
      () => notifier.download(NetworkConsent.mobileData),
      ja.downloadsDownloadComplete,
    );
    await shows(notifier.delete, ja.downloadsDeleted);
  });
}
