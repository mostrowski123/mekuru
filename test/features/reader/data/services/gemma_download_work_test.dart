import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_manga_ocr/local_manga_ocr.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/manga/data/services/model_download_job.dart';
import 'package:mekuru/features/reader/data/services/gemma_translation.dart';
import 'package:mekuru/features/sync/data/services/server_download_work.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:workmanager_platform_interface/workmanager_platform_interface.dart';

import '../../../../shared/fake_download_notifiers.dart';
import '../../../../shared/fake_path_provider.dart';
import '../../../../shared/free_space_fakes.dart';

class _FakeWorkmanager extends WorkmanagerPlatform {
  final registered =
      <
        ({
          String name,
          String task,
          Map<String, dynamic>? input,
          NetworkType? network,
          ExistingWorkPolicy? policy,
        })
      >[];
  final cancelled = <String>[];
  var scheduled = false;
  var scheduledChecks = 0;
  var enqueued = Completer<void>();

  /// When set, an enqueue waits for it after it is recorded.
  Completer<void>? holdEnqueue;

  /// When set, a check whether the job is scheduled waits for it, and
  /// completes [checking] first.
  Completer<void>? holdCheck;
  final checking = Completer<void>();

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
    registered.add((
      name: uniqueName,
      task: taskName,
      input: inputData,
      network: constraints?.networkType,
      policy: existingWorkPolicy,
    ));
    final hold = holdEnqueue;
    if (hold != null) {
      if (!enqueued.isCompleted) enqueued.complete();
      await hold.future;
    }
    scheduled = true;
    if (!enqueued.isCompleted) enqueued.complete();
  }

  @override
  Future<void> cancelByUniqueName(String uniqueName) async {
    cancelled.add(uniqueName);
    scheduled = false;
  }

  @override
  Future<bool> isScheduledByUniqueName(String uniqueName) async {
    scheduledChecks++;
    final hold = holdCheck;
    if (hold != null) {
      if (!checking.isCompleted) checking.complete();
      await hold.future;
    }
    return scheduled;
  }
}

/// The Gemma download as a WorkManager job: the worker against a loopback
/// server with a small stand-in model, and the app following its status.
void main() {
  // The binding answers the mocked Wi-Fi check, but it also makes every
  // HttpClient return 400; the worker needs the real one.
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  group('runGemmaDownloadWork', () {
    // Larger than the server's 8 KB output buffer, so half of it reaches
    // the worker before the rest is sent.
    final payload = List<int>.generate(40000, (i) => i % 251);
    late Directory dir;
    late HttpServer server;
    late Completer<void> halfSent;
    late Completer<void> resume;
    var requests = 0;
    var pause = false;

    ({String name, String url, int bytes, String sha256}) model({
      String? sha,
    }) => (
      name: 'model.bin',
      url: 'http://127.0.0.1:${server.port}/model',
      bytes: payload.length,
      sha256: sha ?? sha256.convert(payload).toString(),
    );

    ServerDownloadWorkDir work() => ServerDownloadWorkDir(dir.path);

    Future<bool> run({String? sha}) =>
        runGemmaDownloadWork({'dir': dir.path}, file: model(sha: sha));

    // The notifications the worker posts, by their arguments.
    final notifications = <Map<Object?, Object?>>[];

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      notifications.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(LocalMangaOcr.channel, (call) async {
            if (call.method != 'postNotification') return null;
            notifications.add(call.arguments as Map<Object?, Object?>);
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(LocalMangaOcr.channel, null),
      );
      dir = Directory.systemTemp.createTempSync('gemma_work_');
      halfSent = Completer<void>();
      resume = Completer<void>();
      requests = 0;
      pause = false;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        requests++;
        final response = request.response;
        if (request.uri.path != '/model') {
          response.statusCode = HttpStatus.serviceUnavailable;
          await response.close();
          return;
        }
        final range = request.headers.value(HttpHeaders.rangeHeader);
        final from = range == null
            ? 0
            : int.parse(range.substring('bytes='.length, range.length - 1));
        if (from > 0) {
          response.statusCode = HttpStatus.partialContent;
          response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $from-${payload.length - 1}/${payload.length}',
          );
        }
        response.contentLength = payload.length - from;
        final half = payload.length ~/ 2;
        if (pause && from < half) {
          response.add(payload.sublist(from, half));
          await response.flush();
          halfSent.complete();
          await resume.future;
          response.add(payload.sublist(half));
        } else {
          response.add(payload.sublist(from));
        }
        await response.close();
      });
      await work().writeStatus(
        const ServerDownloadWorkStatus(state: ServerDownloadWorkState.running),
      );
    });

    tearDown(() async {
      await server.close(force: true);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('reports progress, verifies, installs and reports done', () async {
      pause = true;
      // The worker writes status.json.tmp and renames it over status.json.
      // On Windows a read of status.json during that rename makes the rename
      // fail, so the test reads it only after the folder watch has seen a
      // write of it land, while the paused server holds the worker.
      final seen = <String, int>{};
      final changed = StreamController<void>.broadcast();
      final watch = dir.watch().listen((event) {
        final path = event is FileSystemMoveEvent
            ? event.destination ?? event.path
            : event.path;
        seen.update(p.basename(path), (n) => n + 1, ifAbsent: () => 1);
        changed.add(null);
      });
      addTearDown(watch.cancel);
      // Whether the watch reported [name] more than [times] times, [within].
      Future<bool> saw(String name, Duration within, {int times = 0}) async {
        final deadline = DateTime.now().add(within);
        while ((seen[name] ?? 0) <= times) {
          final left = deadline.difference(DateTime.now());
          if (left <= Duration.zero) return false;
          await changed.stream.first.timeout(left, onTimeout: () {});
        }
        return true;
      }

      // A watch reports nothing until it is live: write a file of the test's
      // own until the watch sees it.
      var live = false;
      for (var i = 0; i < 50 && !live; i++) {
        File(p.join(dir.path, 'watch-live')).writeAsStringSync('$i');
        live = await saw('watch-live', const Duration(milliseconds: 200));
      }
      expect(live, isTrue);
      final done = run();
      // A failed check must not leave the worker running into tearDown.
      addTearDown(() async {
        if (!resume.isCompleted) resume.complete();
        await done;
      });
      await halfSent.future;
      // macOS's watch also reports the status setUp wrote before the watch
      // began, so a report of status.json is not yet the worker's progress
      // write: read after each report until the status has bytes.
      ServerDownloadWorkStatus? midway;
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      var reports = 0;
      while ((midway?.received ?? 0) == 0) {
        final left = deadline.difference(DateTime.now());
        if (!await saw('status.json', left, times: reports)) break;
        // Counted before the read, so a write that lands during it is seen.
        reports = seen['status.json']!;
        // A later progress write can still land during the read, which then
        // fails. Both files in that rename are whole, so read again.
        for (var i = 0; i < 20; i++) {
          if (i > 0) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
          final read = await work().readStatus();
          if (read == null) continue;
          midway = read;
          break;
        }
      }
      expect(midway?.state, ServerDownloadWorkState.running);
      expect(midway?.received, greaterThan(0));
      resume.complete();

      expect(await done, isTrue);
      expect(File(p.join(dir.path, 'model.bin')).readAsBytesSync(), payload);
      expect(File(p.join(dir.path, 'INSTALLED')).existsSync(), isTrue);
      expect(File(p.join(dir.path, 'model.bin.part')).existsSync(), isFalse);
      final status = await work().readStatus();
      expect(status?.state, ServerDownloadWorkState.done);
      expect(status?.received, payload.length);
    });

    test('a file that fails verification is deleted and reported', () async {
      expect(await run(sha: 'not the hash'), isTrue);
      expect(File(p.join(dir.path, 'model.bin.part')).existsSync(), isFalse);
      expect(File(p.join(dir.path, 'INSTALLED')).existsSync(), isFalse);
      final status = await work().readStatus();
      expect(status?.state, ServerDownloadWorkState.failed);
      expect(status?.error, modelJobVerificationError);
    });

    test('giving up posts a notification in the app language', () async {
      SharedPreferences.setMockInitialValues({'app.language': 'es'});
      expect(await run(sha: 'not the hash'), isTrue);
      expect(notifications, hasLength(1));
      expect(
        notifications.single['title'],
        'Falló la descarga de la alta calidad',
      );
      expect(
        notifications.single['text'],
        'Vuelve a intentarlo desde Descargas en Mekuru.',
      );
      expect(notifications.single['channelName'], 'Descargas');
    });

    test('a finished download posts nothing', () async {
      expect(await run(), isTrue);
      expect(notifications, isEmpty);
    });

    test('resumes from the partial file', () async {
      File(
        p.join(dir.path, 'model.bin.part'),
      ).writeAsBytesSync(payload.sublist(0, 10000));
      expect(await run(), isTrue);
      expect(File(p.join(dir.path, 'model.bin')).readAsBytesSync(), payload);
    });

    test('a complete partial file is only checked again', () async {
      File(p.join(dir.path, 'model.bin.part')).writeAsBytesSync(payload);
      expect(await run(), isTrue);
      expect(requests, 0);
      expect(File(p.join(dir.path, 'INSTALLED')).existsSync(), isTrue);
    });

    test('a network failure is retried with the partial file kept', () async {
      final failing = (
        name: 'model.bin',
        url: 'http://127.0.0.1:${server.port}/down',
        bytes: payload.length,
        sha256: 'x',
      );
      expect(
        await runGemmaDownloadWork({'dir': dir.path}, file: failing),
        isFalse,
      );
      final status = await work().readStatus();
      expect(status?.state, ServerDownloadWorkState.running);
      expect(status?.failedAttempts, 1);
    });

    test(
      'a model renamed before its marker was written is installed',
      () async {
        // Stopped between the rename and the marker: the file passed its check.
        File(p.join(dir.path, 'model.bin')).writeAsBytesSync(payload);
        expect(await run(), isTrue);
        expect(requests, 0);
        expect(File(p.join(dir.path, 'INSTALLED')).existsSync(), isTrue);
        expect(
          (await work().readStatus())?.state,
          ServerDownloadWorkState.done,
        );
      },
    );

    test('giving up is logged, without user text', () async {
      final events = <String>[];
      usageLogSinkOverride = (message, _, {required isWarning}) =>
          events.add(message);
      addTearDown(() => usageLogSinkOverride = null);
      expect(await run(sha: 'not the hash'), isTrue);
      // The last try of a failing transfer.
      await work().writeStatus(
        const ServerDownloadWorkStatus(
          state: ServerDownloadWorkState.running,
          failedAttempts: serverDownloadMaxFailedAttempts - 1,
        ),
      );
      final failing = (
        name: 'model.bin',
        url: 'http://127.0.0.1:${server.port}/down',
        bytes: payload.length,
        sha256: 'x',
      );
      expect(
        await runGemmaDownloadWork({'dir': dir.path}, file: failing),
        isTrue,
      );
      expect(events, [
        'translation.high_quality_download_failed',
        'translation.high_quality_download_failed',
      ]);
    });

    test('a missing folder means cancelled', () async {
      dir.deleteSync(recursive: true);
      expect(await run(), isTrue);
      expect(requests, 0);
    });

    test('a stopped status means cancelled', () async {
      await work().writeStatus(
        const ServerDownloadWorkStatus(
          state: ServerDownloadWorkState.failed,
          error: serverDownloadStoppedError,
        ),
      );
      expect(await run(), isTrue);
      expect(requests, 0);
    });
  });

  group('downloadModel follows the job', () {
    final gemma = GemmaTranslation.instance;
    late Directory support;
    late _FakeWorkmanager workmanager;
    const every = Duration(milliseconds: 5);

    // GemmaTranslation works out its folder once per isolate.
    setUpAll(() {
      support = Directory.systemTemp.createTempSync('gemma_follow_');
      PathProviderPlatform.instance = FakePathProviderPlatform(support.path);
    });
    tearDownAll(() => support.deleteSync(recursive: true));

    String modelDir() => p.join(support.path, 'gemma-4-e2b');
    ServerDownloadWorkDir work() => ServerDownloadWorkDir(modelDir());

    // What the job writes. Retried: on Windows renaming the new status over
    // the old one fails while downloadModel is reading it.
    Future<void> jobWrites(ServerDownloadWorkStatus status) async {
      for (var tries = 0; ; tries++) {
        try {
          return await work().writeStatus(status);
        } on FileSystemException {
          if (tries == 100) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
      }
    }

    setUp(() {
      mockWifiConnected(true);
      workmanager = _FakeWorkmanager();
      WorkmanagerPlatform.instance = workmanager;
      final dir = Directory(modelDir());
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('progress from the status file, then installed', () async {
      final fractions = <double>[];
      final done = gemma.downloadModel(
        network: NetworkConsent.wifiOnly,
        onProgress: (fraction, _) => fractions.add(fraction),
        every: every,
      );
      await workmanager.enqueued.future;
      final job = workmanager.registered.single;
      expect(job.name, gemmaDownloadWorkName);
      expect(job.task, gemmaDownloadTaskName);
      expect(job.input, {'dir': modelDir()});
      // No OK for mobile data: WorkManager waits for Wi-Fi if it goes.
      expect(job.network, NetworkType.unmetered);
      // A second start joins the job instead of starting it over.
      expect(job.policy, ExistingWorkPolicy.keep);

      await jobWrites(
        ServerDownloadWorkStatus(
          state: ServerDownloadWorkState.running,
          received: gemmaModelFile.bytes ~/ 2,
          total: gemmaModelFile.bytes,
        ),
      );
      while (!fractions.contains(0.5)) {
        await Future<void>.delayed(every);
      }
      File(p.join(modelDir(), 'INSTALLED')).writeAsStringSync('ok');
      await jobWrites(
        const ServerDownloadWorkStatus(state: ServerDownloadWorkState.done),
      );
      workmanager.scheduled = false;
      await done;
      // Followed to the end, so a later launch doesn't report it again.
      expect(await gemma.downloadPending(), isFalse);
    });

    test('a failed job throws', () async {
      final done = gemma.downloadModel(
        network: NetworkConsent.wifiOnly,
        every: every,
      );
      await workmanager.enqueued.future;
      await jobWrites(
        const ServerDownloadWorkStatus(
          state: ServerDownloadWorkState.failed,
          error: modelJobVerificationError,
        ),
      );
      await expectLater(done, throwsA(isA<FileSystemException>()));
    });

    test('a job that ended without the model throws', () async {
      final done = gemma.downloadModel(
        network: NetworkConsent.wifiOnly,
        every: every,
      );
      await workmanager.enqueued.future;
      workmanager.scheduled = false;
      await expectLater(
        done,
        throwsA(
          isA<ServerDownloadFailedException>().having(
            (e) => e.error,
            'error',
            serverDownloadInterruptedError,
          ),
        ),
      );
    });

    test('cancel stops following and cancels the job', () async {
      final done = gemma.downloadModel(
        network: NetworkConsent.wifiOnly,
        every: every,
      );
      await workmanager.enqueued.future;
      expect(gemma.cancelDownload(), isTrue);
      await expectLater(done, throwsA(isA<HttpException>()));
      // Cancelled twice: by cancelDownload, and again before throwing.
      expect(workmanager.cancelled.toSet(), {gemmaDownloadWorkName});
      expect(workmanager.scheduled, isFalse);
      final status = await work().readStatus();
      expect(status?.error, serverDownloadStoppedError);
    });

    test('the user chose mobile data: any network', () async {
      mockWifiConnected(false);
      final done = gemma.downloadModel(
        network: NetworkConsent.mobileData,
        every: every,
      );
      await workmanager.enqueued.future;
      expect(workmanager.registered.single.network, NetworkType.connected);
      gemma.cancelDownload();
      await expectLater(done, throwsA(isA<HttpException>()));
    });

    test("off Wi-Fi without the user's OK it waits for Wi-Fi", () async {
      // As when a relaunch follows a job that ended meanwhile: queued again
      // without asking, so never over mobile data.
      mockWifiConnected(false);
      final done = gemma.downloadModel(
        network: NetworkConsent.wifiOnly,
        every: every,
      );
      await workmanager.enqueued.future;
      expect(workmanager.registered.single.network, NetworkType.unmetered);
      gemma.cancelDownload();
      await expectLater(done, throwsA(isA<HttpException>()));
    });

    /// Follows a [network] download until [waiting] says what it waits for,
    /// after Wi-Fi went; the last answer.
    Future<JobWait> waitingOffWifi(
      NetworkConsent network, {
      bool alreadyQueued = false,
    }) async {
      final waiting = <JobWait>[];
      final done = gemma.downloadModel(
        network: network,
        onProgress: (_, wait) => waiting.add(wait),
        every: every,
      );
      if (!alreadyQueued) await workmanager.enqueued.future;
      await jobWrites(
        ServerDownloadWorkStatus(
          state: ServerDownloadWorkState.running,
          received: gemmaModelFile.bytes ~/ 4,
          total: gemmaModelFile.bytes,
        ),
      );
      mockWifiConnected(false);
      final seenFrom = waiting.length;
      // Two reports: the first can come from a poll that asked before.
      while (waiting.length < seenFrom + 2) {
        await Future<void>.delayed(every);
      }
      final last = waiting.last;
      gemma.cancelDownload();
      await expectLater(done, throwsA(isA<HttpException>()));
      return last;
    }

    test('queued for Wi-Fi only, it says it waits once Wi-Fi goes', () async {
      expect(await waitingOffWifi(NetworkConsent.wifiOnly), JobWait.wifi);
    });

    test('allowed mobile data, it never says it waits for Wi-Fi', () async {
      expect(await waitingOffWifi(NetworkConsent.mobileData), JobWait.none);
    });

    test('a relaunch following a job allowed mobile data does not say it '
        'waits', () async {
      // The job was queued with the user's OK, before Mekuru closed.
      final first = gemma.downloadModel(
        network: NetworkConsent.mobileData,
        every: every,
      );
      await workmanager.enqueued.future;
      gemma.cancelDownload();
      await expectLater(first, throwsA(isA<HttpException>()));
      workmanager.scheduled = true;
      await jobWrites(
        const ServerDownloadWorkStatus(state: ServerDownloadWorkState.running),
      );

      // Following asks nothing, so it passes Wi-Fi only.
      expect(
        await waitingOffWifi(NetworkConsent.wifiOnly, alreadyQueued: true),
        JobWait.none,
      );
    });

    /// What following a [network] download last reports about waiting once
    /// its job writes [status] (a quarter in), with no network at all when
    /// [offline].
    Future<JobWait> waitFor(
      NetworkConsent network, {
      int failedAttempts = 0,
      bool offline = false,
    }) async {
      final waits = <JobWait>[];
      workmanager.enqueued = Completer<void>();
      final done = gemma.downloadModel(
        network: network,
        onProgress: (_, wait) => waits.add(wait),
        every: every,
      );
      await workmanager.enqueued.future;
      await jobWrites(
        ServerDownloadWorkStatus(
          state: ServerDownloadWorkState.running,
          received: gemmaModelFile.bytes ~/ 4,
          total: gemmaModelFile.bytes,
          failedAttempts: failedAttempts,
        ),
      );
      if (offline) mockWifiConnected(false, offline: true);
      final seenFrom = waits.length;
      // Two reports: the first can come from a poll that read before.
      while (waits.length < seenFrom + 2) {
        await Future<void>.delayed(every);
      }
      final last = waits.last;
      gemma.cancelDownload();
      await expectLater(done, throwsA(isA<HttpException>()));
      return last;
    }

    test('a job waiting out its retry, or allowed mobile data with no network '
        'at all, says so', () async {
      // Was: all three reported as waiting for nothing (false).
      expect(await waitFor(NetworkConsent.wifiOnly), JobWait.none);
      // Its last attempt failed: WorkManager runs it again after a backoff.
      expect(
        await waitFor(NetworkConsent.wifiOnly, failedAttempts: 1),
        JobWait.retry,
      );
      expect(
        await waitFor(NetworkConsent.mobileData, offline: true),
        JobWait.connection,
      );
      // No network says more than the failed attempt it led to.
      expect(
        await waitFor(
          NetworkConsent.mobileData,
          failedAttempts: 1,
          offline: true,
        ),
        JobWait.connection,
      );
    });

    test('a cancel while the job is being queued still cancels it', () async {
      workmanager.holdEnqueue = Completer<void>();
      final done = gemma.downloadModel(
        network: NetworkConsent.wifiOnly,
        every: every,
      );
      await workmanager.enqueued.future;
      gemma.cancelDownload();
      workmanager.holdEnqueue!.complete();
      await expectLater(done, throwsA(isA<HttpException>()));
      expect(workmanager.scheduled, isFalse);
    });

    test('a cancel while WorkManager is asked about the job is a cancel, '
        'not an interruption', () async {
      final done = gemma.downloadModel(
        network: NetworkConsent.wifiOnly,
        every: every,
      );
      await workmanager.enqueued.future;
      workmanager.holdCheck = Completer<void>();
      await workmanager.checking.future;
      // The cancel removes the job, so the pending check answers no.
      gemma.cancelDownload();
      workmanager.holdCheck!.complete();
      await expectLater(done, throwsA(isA<HttpException>()));
    });

    test('a job already queued is only followed', () async {
      // Mekuru restarted mid-download: the job holds the folder.
      workmanager.scheduled = true;
      // A space check now would fail: the running job already uses it.
      mockFreeBytes(1);
      Directory(modelDir()).createSync(recursive: true);
      final fractions = <double>[];
      final done = gemma.downloadModel(
        network: NetworkConsent.wifiOnly,
        onProgress: (fraction, _) => fractions.add(fraction),
        every: every,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(workmanager.registered, isEmpty);
      expect(File(p.join(modelDir(), 'status.json')).existsSync(), isFalse);
      await jobWrites(
        ServerDownloadWorkStatus(
          state: ServerDownloadWorkState.running,
          received: gemmaModelFile.bytes ~/ 4,
          total: gemmaModelFile.bytes,
        ),
      );
      while (!fractions.contains(0.25)) {
        await Future<void>.delayed(every);
      }
      File(p.join(modelDir(), 'INSTALLED')).writeAsStringSync('ok');
      await jobWrites(
        const ServerDownloadWorkStatus(state: ServerDownloadWorkState.done),
      );
      workmanager.scheduled = false;
      await done;
    });

    test('WorkManager is asked about the job only now and then', () async {
      final done = gemma.downloadModel(
        network: NetworkConsent.wifiOnly,
        every: every,
      );
      await workmanager.enqueued.future;
      // About 20 polls.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(workmanager.scheduledChecks, lessThanOrEqualTo(4));
      gemma.cancelDownload();
      await expectLater(done, throwsA(isA<HttpException>()));
    });

    test('a running job, or one finished unseen, is pending', () async {
      workmanager.scheduled = true;
      // No download running: WorkManager, which answers on the main thread,
      // isn't asked.
      expect(await gemma.downloadPending(), isFalse);
      expect(workmanager.scheduledChecks, 0);
      Directory(modelDir()).createSync(recursive: true);
      await work().writeStatus(
        const ServerDownloadWorkStatus(state: ServerDownloadWorkState.running),
      );
      expect(await gemma.downloadPending(), isTrue);
      workmanager.scheduled = false;
      expect(await gemma.downloadPending(), isFalse);
      await work().writeStatus(
        const ServerDownloadWorkStatus(state: ServerDownloadWorkState.done),
      );
      // Reported once.
      expect(await gemma.downloadPending(), isTrue);
      expect(await gemma.downloadPending(), isFalse);
    });
  });
}
