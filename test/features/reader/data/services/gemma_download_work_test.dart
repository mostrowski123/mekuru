import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/reader/data/services/gemma_translation.dart';
import 'package:mekuru/features/sync/data/services/server_download_work.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:workmanager_platform_interface/workmanager_platform_interface.dart';

import '../../../../shared/fake_download_notifiers.dart';
import '../../../../shared/fake_path_provider.dart';

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

    setUp(() async {
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
      final done = run();
      await halfSent.future;
      // Read once, after the first chunk's write: on Windows a read while
      // the worker renames the new status over the old one makes it fail.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final midway = await work().readStatus();
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
      expect(status?.error, gemmaVerificationError);
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
      final done = gemma.downloadModel(onProgress: fractions.add, every: every);
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
      final done = gemma.downloadModel(every: every);
      await workmanager.enqueued.future;
      await jobWrites(
        const ServerDownloadWorkStatus(
          state: ServerDownloadWorkState.failed,
          error: gemmaVerificationError,
        ),
      );
      await expectLater(done, throwsA(isA<FileSystemException>()));
    });

    test('a job that ended without the model throws', () async {
      final done = gemma.downloadModel(every: every);
      await workmanager.enqueued.future;
      workmanager.scheduled = false;
      await expectLater(done, throwsA(isA<HttpException>()));
    });

    test('cancel stops following and cancels the job', () async {
      final done = gemma.downloadModel(every: every);
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
      final done = gemma.downloadModel(mobileData: true, every: every);
      await workmanager.enqueued.future;
      expect(workmanager.registered.single.network, NetworkType.connected);
      gemma.cancelDownload();
      await expectLater(done, throwsA(isA<HttpException>()));
    });

    test("off Wi-Fi without the user's OK it waits for Wi-Fi", () async {
      // As when a relaunch follows a job that ended meanwhile: queued again
      // without asking, so never over mobile data.
      mockWifiConnected(false);
      final done = gemma.downloadModel(every: every);
      await workmanager.enqueued.future;
      expect(workmanager.registered.single.network, NetworkType.unmetered);
      gemma.cancelDownload();
      await expectLater(done, throwsA(isA<HttpException>()));
    });

    test('a cancel while the job is being queued still cancels it', () async {
      workmanager.holdEnqueue = Completer<void>();
      final done = gemma.downloadModel(every: every);
      await workmanager.enqueued.future;
      gemma.cancelDownload();
      workmanager.holdEnqueue!.complete();
      await expectLater(done, throwsA(isA<HttpException>()));
      expect(workmanager.scheduled, isFalse);
    });

    test('a job already queued is only followed', () async {
      // Mekuru restarted mid-download: the job holds the folder.
      workmanager.scheduled = true;
      const saf = MethodChannel('mekuru/android_saf');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      // A space check now would fail: the running job already uses it.
      messenger.setMockMethodCallHandler(
        saf,
        (call) async => call.method == 'getFreeBytes' ? 1 : null,
      );
      addTearDown(() => messenger.setMockMethodCallHandler(saf, null));
      Directory(modelDir()).createSync(recursive: true);
      final fractions = <double>[];
      final done = gemma.downloadModel(onProgress: fractions.add, every: every);
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
      final done = gemma.downloadModel(every: every);
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
