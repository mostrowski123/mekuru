import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/features/reader/presentation/providers/gemma_download_provider.dart';

void main() {
  late bool installed;
  late Completer<void> download;
  late void Function(double) report;
  late int cancels;
  late int deletes;
  late bool hasFiles;

  setUp(() {
    installed = false;
    hasFiles = false;
    cancels = 0;
    deletes = 0;
    download = Completer<void>();
    debugGemmaModelOps = (
      installed: () async => installed,
      download: (onProgress) {
        report = onProgress;
        return download.future;
      },
      delete: () async {
        deletes++;
        installed = false;
      },
      hasFiles: () async => hasFiles,
      cancel: () {
        cancels++;
        // What force-closing the HttpClient does to the running download.
        download.completeError(StateError('Client is closed'));
        return true;
      },
    );
  });
  tearDown(() => debugGemmaModelOps = null);

  test('progress, then installed', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final done = c.read(gemmaDownloadProvider.notifier).start();
    await Future<void>.delayed(Duration.zero);
    report(0.45);
    expect(
      c.read(gemmaDownloadProvider),
      isA<GemmaDownloading>().having((s) => s.fraction, 'fraction', 0.45),
    );
    installed = true;
    download.complete();
    await done;
    expect(c.read(gemmaDownloadProvider), isA<GemmaInstalled>());
  });

  test('losing Wi-Fi fails with the reason and can start again', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final done = c.read(gemmaDownloadProvider.notifier).start();
    download.completeError(const WifiLostException());
    await done;
    expect(
      c.read(gemmaDownloadProvider),
      isA<GemmaDownloadFailed>().having(
        (s) => s.error,
        'error',
        isA<WifiLostException>(),
      ),
    );
    download = Completer<void>();
    unawaited(c.read(gemmaDownloadProvider.notifier).start());
    await Future<void>.delayed(Duration.zero);
    expect(c.read(gemmaDownloadProvider), isA<GemmaDownloading>());
  });

  test('a second start while downloading is ignored', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    var starts = 0;
    debugGemmaModelOps = (
      installed: () async => false,
      download: (_) {
        starts++;
        return download.future;
      },
      delete: () async {},
      hasFiles: () async => false,
      cancel: () => false,
    );
    unawaited(c.read(gemmaDownloadProvider.notifier).start());
    unawaited(c.read(gemmaDownloadProvider.notifier).start());
    await Future<void>.delayed(Duration.zero);
    expect(starts, 1);
  });

  test('start with the model already there downloads nothing', () async {
    var starts = 0;
    debugGemmaModelOps = (
      installed: () async => true,
      download: (_) {
        starts++;
        return download.future;
      },
      delete: () async {},
      hasFiles: () async => false,
      cancel: () => false,
    );
    final c = ProviderContainer();
    addTearDown(c.dispose);
    unawaited(c.read(gemmaDownloadProvider.notifier).start());
    await Future<void>.delayed(Duration.zero);
    expect(starts, 0);
    expect(c.read(gemmaDownloadProvider), isA<GemmaInstalled>());
  });

  test(
    'the first install check does not overwrite a started download',
    () async {
      final check = Completer<bool>();
      debugGemmaModelOps = (
        installed: () => check.future,
        download: (_) => download.future,
        delete: () async {},
        hasFiles: () async => false,
        cancel: () => false,
      );
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(gemmaDownloadProvider);
      unawaited(c.read(gemmaDownloadProvider.notifier).start());
      check.complete(false);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(gemmaDownloadProvider), isA<GemmaDownloading>());
    },
  );

  test('remove deletes the model', () async {
    installed = true;
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(gemmaDownloadProvider);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(gemmaDownloadProvider), isA<GemmaInstalled>());
    await c.read(gemmaDownloadProvider.notifier).remove();
    expect(installed, isFalse);
    expect(c.read(gemmaDownloadProvider), isA<GemmaNotInstalled>());
  });

  test('cancel stops the download, which can start again', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final done = c.read(gemmaDownloadProvider.notifier).start();
    await Future<void>.delayed(Duration.zero);
    c.read(gemmaDownloadProvider.notifier).cancel();
    await done;
    expect(cancels, 1);
    expect(c.read(gemmaDownloadProvider), isA<GemmaNotInstalled>());
    download = Completer<void>();
    unawaited(c.read(gemmaDownloadProvider.notifier).start());
    await Future<void>.delayed(Duration.zero);
    expect(c.read(gemmaDownloadProvider), isA<GemmaDownloading>());
  });

  test('a cancelled download leaves its partial file to remove', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final done = c.read(gemmaDownloadProvider.notifier).start();
    await Future<void>.delayed(Duration.zero);
    hasFiles = true;
    c.read(gemmaDownloadProvider.notifier).cancel();
    await done;
    expect(
      c.read(gemmaDownloadProvider),
      isA<GemmaNotInstalled>().having((s) => s.hasFiles, 'hasFiles', isTrue),
    );
    await c.read(gemmaDownloadProvider.notifier).remove();
    expect(deletes, 1);
    expect(
      c.read(gemmaDownloadProvider),
      isA<GemmaNotInstalled>().having((s) => s.hasFiles, 'hasFiles', isFalse),
    );
  });

  test('the install check finds files left by an earlier run', () async {
    hasFiles = true;
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(gemmaDownloadProvider);
    await Future<void>.delayed(Duration.zero);
    expect(
      c.read(gemmaDownloadProvider),
      isA<GemmaNotInstalled>().having((s) => s.hasFiles, 'hasFiles', isTrue),
    );
  });

  test('cancel when not downloading does nothing', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(gemmaDownloadProvider.notifier).cancel();
    await Future<void>.delayed(Duration.zero);
    expect(cancels, 0);
    expect(c.read(gemmaDownloadProvider), isA<GemmaNotInstalled>());
  });

  test('remove during a download is ignored', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    unawaited(c.read(gemmaDownloadProvider.notifier).start());
    await Future<void>.delayed(Duration.zero);
    await c.read(gemmaDownloadProvider.notifier).remove();
    expect(deletes, 0);
    expect(c.read(gemmaDownloadProvider), isA<GemmaDownloading>());
  });

  test('a cancel that closed nothing does not hide a failure', () async {
    debugGemmaModelOps = (
      installed: () async => false,
      download: (_) => download.future,
      delete: () async {},
      hasFiles: () async => false,
      cancel: () => false,
    );
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final done = c.read(gemmaDownloadProvider.notifier).start();
    await Future<void>.delayed(Duration.zero);
    c.read(gemmaDownloadProvider.notifier).cancel();
    download.completeError(const FileSystemException('verification'));
    await done;
    expect(c.read(gemmaDownloadProvider), isA<GemmaDownloadFailed>());
  });

  test('a new download forgets an earlier cancel', () async {
    // The cancel closed a client, yet the download still finished.
    debugGemmaModelOps = (
      installed: () async => false,
      download: (_) => download.future,
      delete: () async {},
      hasFiles: () async => false,
      cancel: () => true,
    );
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final first = c.read(gemmaDownloadProvider.notifier).start();
    await Future<void>.delayed(Duration.zero);
    c.read(gemmaDownloadProvider.notifier).cancel();
    download.complete();
    await first;
    expect(c.read(gemmaDownloadProvider), isA<GemmaInstalled>());
    await c.read(gemmaDownloadProvider.notifier).remove();
    download = Completer<void>();
    final second = c.read(gemmaDownloadProvider.notifier).start();
    download.completeError(const WifiLostException());
    await second;
    expect(c.read(gemmaDownloadProvider), isA<GemmaDownloadFailed>());
  });

  test('a slow install check does not overwrite a newer state', () async {
    var check = Completer<bool>();
    var slow = true;
    debugGemmaModelOps = (
      installed: () => slow ? check.future : Future.value(false),
      download: (_) => download.future,
      delete: () async {},
      hasFiles: () async => false,
      cancel: () => false,
    );
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final notifier = c.read(gemmaDownloadProvider.notifier);
    // build()'s check is still running when a download finishes; start()'s
    // own check answers at once.
    slow = false;
    final done = notifier.start();
    download.complete();
    await done;
    check.complete(false);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(gemmaDownloadProvider), isA<GemmaInstalled>());
    // A check still running when the model is deleted.
    check = Completer<bool>();
    slow = true;
    unawaited(notifier.refresh());
    await notifier.remove();
    check.complete(true);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(gemmaDownloadProvider), isA<GemmaNotInstalled>());
  });
}
