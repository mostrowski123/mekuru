import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/features/backup/data/services/full_backup_service.dart'
    show InsufficientSpaceException;
import 'package:mekuru/features/manga/data/services/model_download.dart';
import 'package:mekuru/features/sync/data/services/server_download_work.dart';
import 'package:mekuru/features/word_audio/data/services/word_audio.dart';
import 'package:mekuru/features/word_audio/data/services/word_audio_pack.dart';
import 'package:mekuru/features/word_audio/presentation/providers/word_audio_providers.dart';
import 'package:mekuru/features/word_audio/presentation/widgets/word_audio_download_tile.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqlite3/sqlite3.dart';
// ignore: depend_on_referenced_packages
import 'package:workmanager_platform_interface/workmanager_platform_interface.dart';

import '../../shared/fake_download_notifiers.dart';
import '../../shared/fake_path_provider.dart';
import '../../test_app.dart';

const _clip = 'f84aff2662b3f2f2';
const _clipBytes = [7, 8, 9];

/// A pack's download driven by the test, on top of a word list already there.
class _FakePack extends WordAudioPack {
  var isInstalled = false;
  var filesThere = false;
  var isPending = false;
  var cancels = 0;
  var deletes = 0;
  var deleteFails = false;
  bool? lastMobileData;
  void Function(double)? report;
  void Function(double fraction, bool waitingForWifi)? progress;
  Completer<void>? transfer;

  @override
  Future<bool> get installed async => isInstalled;

  @override
  Future<bool> hasFiles() async => filesThere;

  @override
  Future<bool> pending() async => isPending;

  @override
  String get downloadSize => '2.3 GB';

  @override
  Future<void> download({
    required NetworkConsent network,
    void Function(double fraction, bool waitingForWifi)? onProgress,
  }) {
    lastMobileData = network.allowsMobileData;
    progress = onProgress;
    report = onProgress == null ? null : (f) => onProgress(f, false);
    filesThere = true;
    return (transfer = Completer<void>()).future;
  }

  @override
  bool cancel() {
    cancels++;
    transfer?.completeError(const HttpException('closed'));
    return true;
  }

  @override
  Future<void> delete() async {
    deletes++;
    if (deleteFails) throw const FileSystemException('locked', '/data/pack');
    filesThere = false;
    isInstalled = false;
  }
}

/// WorkManager that only keeps whether the pack's job is queued.
class _QueuedWorkmanager extends WorkmanagerPlatform {
  var scheduled = false;
  final queued = Completer<void>();

  @override
  Future<void> registerOneOffTask(
    String uniqueName,
    String taskName, {
    Map<String, dynamic>? inputData,
    Duration? initialDelay,
    Constraints? constraints,
    ExistingWorkPolicy? existingWorkPolicy,
    BackoffPolicy? backoffPolicy,
    Duration? backoffPolicyDelay,
    String? tag,
    OutOfQuotaPolicy? outOfQuotaPolicy,
  }) async {
    scheduled = true;
    if (!queued.isCompleted) queued.complete();
  }

  @override
  Future<void> cancelByUniqueName(String uniqueName) async => scheduled = false;

  @override
  Future<bool> isScheduledByUniqueName(String uniqueName) async => scheduled;
}

class _FakeAudio extends WordAudio {
  _FakeAudio(_FakePack pack) : super(pack: pack);

  var wordListThere = true;
  bool? wordListWifiOnly;

  @override
  Future<bool> get installed async => wordListThere;

  @override
  Future<void> download({
    required NetworkConsent network,
    void Function(double)? onProgress,
  }) async {
    wordListThere = true;
    wordListWifiOnly = network == NetworkConsent.wifiOnly;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The test binding answers all HTTP with 400; these talk to a real socket.
  HttpOverrides.global = null;

  group('reading clips', () {
    late Directory root;
    late Directory packDir;

    setUp(() async {
      root = Directory.systemTemp.createTempSync('word_audio_pack');
      final support = Directory(p.join(root.path, 'support'))..createSync();
      PathProviderPlatform.instance = FakePathProviderPlatform(support.path);
      packDir = await Directory(
        await WordAudioPack.storageDir(),
      ).create(recursive: true);
    });

    tearDown(() => root.deleteSync(recursive: true));

    File buildPack() {
      final file = File(p.join(packDir.path, wordAudioPackFile.name));
      final db = sqlite3.open(file.path);
      db.execute('CREATE TABLE clip(id BLOB PRIMARY KEY, mp3 BLOB NOT NULL)');
      db.execute('INSERT INTO clip VALUES (?, ?)', [
        Uint8List.fromList(const [
          0xf8,
          0x4a,
          0xff,
          0x26,
          0x62,
          0xb3,
          0xf2,
          0xf2,
        ]),
        Uint8List.fromList(_clipBytes),
      ]);
      db.close();
      return file;
    }

    test('an installed pack answers without the network', () async {
      buildPack();
      File(p.join(packDir.path, modelInstalledMarker)).writeAsStringSync('ok');
      // Nothing listens there: the network would throw.
      final audio = WordAudio(base: 'http://127.0.0.1:9/v1');
      addTearDown(audio.dispose);

      final clip = await audio.clipFile(_clip);

      expect(clip.source, 'pack');
      expect(File(clip.path).readAsBytesSync(), _clipBytes);
      expect((await audio.clipFile(_clip)).source, 'cache');
    });

    test('a pack still downloading is not read', () async {
      buildPack();
      final audio = WordAudio(base: 'http://127.0.0.1:9/v1');
      addTearDown(audio.dispose);

      await expectLater(audio.clipFile(_clip), throwsA(isA<SocketException>()));
    });

    group('an older pin', () {
      File older(String name) =>
          File(p.join(packDir.path, name))..writeAsStringSync('old');
      void markInstalled() => File(
        p.join(packDir.path, modelInstalledMarker),
      ).writeAsStringSync('ok');

      test('goes, and leaves nothing that says installed', () async {
        final pack = older('word_audio_pack_2026-07-27.sqlite');
        final partial = older('word_audio_pack_2026-01-01.sqlite.part');
        markInstalled();
        await ServerDownloadWorkDir(packDir.path).writeStatus(
          const ServerDownloadWorkStatus(
            state: ServerDownloadWorkState.done,
            received: 1,
            total: 1,
          ),
        );
        final current = WordAudioPack();

        expect(await current.installed, isFalse);
        expect(await current.clip(const [1]), isNull);
        expect(await current.pending(), isFalse);
        expect(await current.hasFiles(), isFalse);
        expect(pack.existsSync(), isFalse);
        expect(partial.existsSync(), isFalse);
      });

      test('goes without touching the current pack', () async {
        final pack = older('word_audio_pack_2026-07-27.sqlite');
        buildPack();
        markInstalled();
        final current = WordAudioPack();
        addTearDown(current.close);

        expect(await current.installed, isTrue);
        expect(await current.clip(const [1]), isNull);
        expect(pack.existsSync(), isFalse);
      });

      test('goes without touching a partial download to resume', () async {
        final pack = older('word_audio_pack_2026-07-27.sqlite');
        final partial = older('${wordAudioPackFile.name}.part');
        final current = WordAudioPack();

        expect(await current.hasFiles(), isTrue);
        expect(partial.existsSync(), isTrue);
        expect(pack.existsSync(), isFalse);
      });
    });

    test('deleting takes the folder and the open file with it', () async {
      buildPack();
      File(p.join(packDir.path, modelInstalledMarker)).writeAsStringSync('ok');
      final pack = WordAudioPack();
      expect(await pack.clip(const [1]), isNull);

      await pack.delete();

      expect(await pack.installed, isFalse);
      expect(await pack.hasFiles(), isFalse);
    });
  });

  group('the download', () {
    late Directory root;
    late HttpServer server;
    late Uint8List body;
    late WordAudioPack pack;
    late ModelFile file;
    Completer<void>? gate;
    var requests = 0;
    var ranges = <String?>[];

    setUp(() async {
      root = Directory.systemTemp.createTempSync('word_audio_pack_dl');
      final support = Directory(p.join(root.path, 'support'))..createSync();
      PathProviderPlatform.instance = FakePathProviderPlatform(support.path);
      // Over 8 KB, so part of it really leaves the server's buffer.
      body = Uint8List.fromList(List.generate(64 * 1024, (i) => i % 251));
      requests = 0;
      ranges = [];
      gate = null;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        requests++;
        final response = request.response;
        final range = request.headers.value(HttpHeaders.rangeHeader);
        ranges.add(range);
        var start = 0;
        if (range != null) {
          start = int.parse(range.substring(6, range.length - 1));
          response.statusCode = HttpStatus.partialContent;
          response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $start-${body.length - 1}/${body.length}',
          );
        }
        response.headers.set(HttpHeaders.etagHeader, '"v1"');
        response.contentLength = body.length - start;
        final held = gate;
        if (held == null) {
          response.add(body.sublist(start));
          await response.close();
          return;
        }
        // Half, then hold the connection open until the test closes it.
        response.add(body.sublist(start, start + (body.length - start) ~/ 2));
        await response.flush();
        await held.future;
        await response.close();
      });
      file = (
        name: 'pack.sqlite',
        url: 'http://127.0.0.1:${server.port}/pack.sqlite',
        bytes: body.length,
        sha256: sha256.convert(body).toString(),
      );
      pack = WordAudioPack(file: file);
    });

    tearDown(() async {
      debugDefaultTargetPlatformOverride = null;
      await server.close(force: true);
      root.deleteSync(recursive: true);
    });

    /// iOS downloads in the app; these channels answer for the platform.
    void onIos({int? free}) {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      mockWifiConnected(true);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const files = MethodChannel('mekuru/ios_files');
      const work = MethodChannel('mekuru/background_work');
      messenger.setMockMethodCallHandler(files, (_) async => free);
      messenger.setMockMethodCallHandler(work, (_) async => true);
      addTearDown(() {
        messenger.setMockMethodCallHandler(files, null);
        messenger.setMockMethodCallHandler(work, null);
      });
    }

    Future<void> waitForPartial() async {
      final part = File(
        p.join(await WordAudioPack.storageDir(), '${file.name}.part'),
      );
      for (var i = 0; i < 200; i++) {
        if (await part.exists() && await part.length() > 0) return;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      fail('nothing arrived');
    }

    test('iOS: installs in the app and verifies', () async {
      onIos();
      final seen = <double>[];

      await pack.download(
        network: NetworkConsent.wifiOnly,
        onProgress: (fraction, _) => seen.add(fraction),
      );

      expect(await pack.installed, isTrue);
      expect(seen.last, 1);
    });

    test('iOS: no room says how much more it needs', () async {
      onIos(free: 10);
      await expectLater(
        pack.download(network: NetworkConsent.wifiOnly),
        throwsA(
          isA<InsufficientSpaceException>().having(
            (e) => e.neededBytes,
            'neededBytes',
            body.length - 10,
          ),
        ),
      );
      expect(requests, 0);
    });

    test(
      'iOS: a cancel keeps the partial file, and the next one resumes',
      () async {
        onIos();
        gate = Completer<void>();
        final download = pack.download(network: NetworkConsent.wifiOnly);
        final failed = expectLater(download, throwsA(anything));
        await waitForPartial();

        expect(pack.cancel(), isTrue);
        await failed;
        expect(await pack.installed, isFalse);
        expect(await pack.hasFiles(), isTrue);

        gate = null;
        await pack.download(network: NetworkConsent.wifiOnly);

        expect(await pack.installed, isTrue);
        expect(ranges.last, startsWith('bytes='));
      },
    );

    test(
      'iOS: the system ending the background task reads as stopped',
      () async {
        onIos();
        gate = Completer<void>();
        final failed = expectLater(
          pack.download(network: NetworkConsent.wifiOnly),
          throwsA(
            isA<ServerDownloadFailedException>().having(
              (e) => e.error,
              'error',
              serverDownloadStoppedError,
            ),
          ),
        );
        await waitForPartial();

        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
              'mekuru/background_work',
              const StandardMethodCodec().encodeMethodCall(
                const MethodCall('expired'),
              ),
              (_) {},
            );
        await failed;
        expect(await pack.hasFiles(), isTrue);
      },
    );

    test('Android: a job queued for Wi-Fi only says it waits once Wi-Fi '
        'goes', () async {
      mockWifiConnected(true);
      final workmanager = _QueuedWorkmanager();
      WorkmanagerPlatform.instance = workmanager;
      final waiting = <bool>[];

      final done = pack.download(
        network: NetworkConsent.wifiOnly,
        onProgress: (_, waitingForWifi) => waiting.add(waitingForWifi),
      );
      await workmanager.queued.future;
      mockWifiConnected(false);
      // The app looks at the job once a second.
      await Future<void>.delayed(const Duration(milliseconds: 2500));

      expect(waiting.last, isTrue);
      pack.cancel();
      await expectLater(done, throwsA(isA<HttpException>()));
    });

    test('Android: the worker installs what the app queued', () async {
      final dir = await Directory(
        await WordAudioPack.storageDir(),
      ).create(recursive: true);
      await ServerDownloadWorkDir(dir.path).writeStatus(
        ServerDownloadWorkStatus(
          state: ServerDownloadWorkState.running,
          received: 0,
          total: body.length,
        ),
      );

      final over = await runWordAudioPackWork({'dir': dir.path}, file: file);

      expect(over, isTrue);
      expect(await pack.installed, isTrue);
      expect(
        (await ServerDownloadWorkDir(dir.path).readStatus())?.state,
        ServerDownloadWorkState.done,
      );
    });
  });

  group('the notifier', () {
    late _FakePack pack;
    late _FakeAudio audio;
    late ProviderContainer container;

    setUp(() {
      pack = _FakePack();
      audio = _FakeAudio(pack);
      container = ProviderContainer(
        overrides: [wordAudioProvider.overrideWithValue(audio)],
      );
    });

    tearDown(() => container.dispose());

    WordAudioPackState read() => container.read(wordAudioPackProvider);
    WordAudioPackNotifier notifier() =>
        container.read(wordAudioPackProvider.notifier);

    test('reports what is on disk', () async {
      pack.isInstalled = true;
      pack.filesThere = true;
      read();
      await pumpEventQueue();
      expect(read().installed, isTrue);
    });

    test('follows a job already running', () async {
      pack.isPending = true;
      read();
      await pumpEventQueue();
      expect(read().fraction, 0);
      expect(pack.lastMobileData, isFalse);
    });

    test('progress, then installed', () async {
      read();
      final start = notifier().start(NetworkConsent.wifiOnly);
      await pumpEventQueue();
      pack.report!(0.5);
      expect(read().fraction, 0.5);

      pack.isInstalled = true;
      pack.transfer!.complete();
      await start;

      expect(read().installed, isTrue);
      expect(read().fraction, isNull);
    });

    test('brings the word list along, on the same terms', () async {
      audio.wordListThere = false;
      read();
      final start = notifier().start(NetworkConsent.mobileData);
      await pumpEventQueue();

      expect(audio.wordListWifiOnly, isFalse);
      expect(pack.lastMobileData, isTrue);
      notifier().cancel();
      await start;
    });

    test('a cancel is no error, and the partial file can go', () async {
      read();
      final start = notifier().start(NetworkConsent.wifiOnly);
      await pumpEventQueue();

      notifier().cancel();
      await start;

      expect(read().error, isNull);
      expect(read().fraction, isNull);
      expect(read().hasFiles, isTrue);

      await notifier().remove();
      expect(pack.deletes, 1);
      expect(read().hasFiles, isFalse);
    });

    test('a failure is kept for the row', () async {
      read();
      final start = notifier().start(NetworkConsent.wifiOnly);
      await pumpEventQueue();

      pack.transfer!.completeError(const SocketException('offline'));
      await start;

      expect(read().error, isA<SocketException>());
      expect(read().fraction, isNull);
    });

    test('removing is ignored while it downloads', () async {
      read();
      final start = notifier().start(NetworkConsent.wifiOnly);
      await pumpEventQueue();

      await notifier().remove();

      expect(pack.deletes, 0);
      notifier().cancel();
      await start;
    });
  });

  group('the row', () {
    late _FakePack pack;

    setUp(() {
      pack = _FakePack();
      mockWifiConnected(true);
    });

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [wordAudioProvider.overrideWithValue(_FakeAudio(pack))],
          child: buildLocalizedTestApp(
            home: const Scaffold(body: WordAudioPackTile()),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('warns about the size before it starts', (tester) async {
      await pump(tester);
      expect(find.textContaining('2.3 GB'), findsOneWidget);

      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();
      expect(find.textContaining('stays on your device'), findsOneWidget);
      expect(pack.lastMobileData, isNull);

      await tester.tap(find.widgetWithText(FilledButton, 'Download').last);
      await tester.pump();
      await tester.pump();
      expect(pack.lastMobileData, isFalse);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);

      pack.cancel();
      await tester.pump();
      await tester.pump();
    });

    testWidgets('off Wi-Fi it asks about mobile data too', (tester) async {
      mockWifiConnected(false);
      await pump(tester);

      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Download').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('mobile data'), findsWidgets);

      await tester.tap(find.widgetWithText(FilledButton, 'Download').last);
      await tester.pump();
      await tester.pump();
      expect(pack.lastMobileData, isTrue);

      pack.cancel();
      await tester.pump();
      await tester.pump();
    });

    testWidgets('installed: Remove, and it says it works offline', (
      tester,
    ) async {
      pack.isInstalled = true;
      await pump(tester);

      expect(find.textContaining('works offline'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pump();
      await tester.pump();

      expect(pack.deletes, 1);
      expect(find.text('Download'), findsOneWidget);
    });

    testWidgets('in Japanese, a failed remove says so and keeps Remove', (
      tester,
    ) async {
      final ja = lookupAppLocalizations(const Locale('ja'));
      pack.isInstalled = true;
      pack.filesThere = true;
      pack.deleteFails = true;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [wordAudioProvider.overrideWithValue(_FakeAudio(pack))],
          child: buildLocalizedTestApp(
            home: const Scaffold(body: WordAudioPackTile()),
            locale: const Locale('ja'),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pump();
      await tester.pump();

      expect(pack.deletes, 1);
      expect(find.text(ja.downloadsDeleteFailed), findsOneWidget);
      expect(untranslatedDownloadText, findsNothing);
      expect(find.textContaining('/data/'), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);

      pack.deleteFails = false;
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pump();
      await tester.pump();
      expect(pack.deletes, 2);
      expect(find.text(ja.downloadsDeleteFailed), findsNothing);
      expect(find.text(ja.commonDownload), findsOneWidget);
    });

    testWidgets('Android: a job waiting for Wi-Fi says so and offers Cancel', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Download').last);
      await tester.pump();
      await tester.pump();

      pack.progress!(0.2, true);
      await tester.pump();

      expect(
        find.text('Waiting for Wi-Fi. Cancel and resume to use mobile data.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.close), findsOneWidget);
      pack.cancel();
      await tester.pump();
      await tester.pump();
    });

    testWidgets('iOS: Wi-Fi going mid-download says what it kept', (
      tester,
    ) async {
      // On Android the job waits for Wi-Fi instead.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await pump(tester);
        await tester.tap(find.text('Download'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Download').last);
        await tester.pump();
        await tester.pump();

        pack.transfer!.completeError(const WifiLostException());
        await tester.pump();
        await tester.pump();

        // The partial file is kept, so the next tap continues it.
        expect(find.textContaining('try again'), findsNothing);
        expect(
          find.text(
            'The download stopped because Wi-Fi disconnected. Finished files '
            'are kept. Tap Download to continue.',
          ),
          findsOneWidget,
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a partial download offers both Remove and Download', (
      tester,
    ) async {
      pack.filesThere = true;
      await pump(tester);

      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      expect(find.text('Download'), findsOneWidget);
    });
  });
}
