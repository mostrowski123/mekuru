import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/features/reader/presentation/providers/gemma_download_provider.dart';

void main() {
  late bool installed;
  late Completer<void> download;
  late void Function(double) report;

  setUp(() {
    installed = false;
    download = Completer<void>();
    debugGemmaModelOps = (
      installed: () async => installed,
      download: (onProgress) {
        report = onProgress;
        return download.future;
      },
      delete: () async => installed = false,
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
    );
    unawaited(c.read(gemmaDownloadProvider.notifier).start());
    unawaited(c.read(gemmaDownloadProvider.notifier).start());
    await Future<void>.delayed(Duration.zero);
    expect(starts, 1);
  });

  test(
    'the first install check does not overwrite a started download',
    () async {
      final check = Completer<bool>();
      debugGemmaModelOps = (
        installed: () => check.future,
        download: (_) => download.future,
        delete: () async {},
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
}
