// A reading mode chosen while a rebuilt viewer still loads is not lost: once
// that viewer is done loading, a viewer for the mode now chosen takes its
// place and shows the page it was opened at. The page's `loaded` calls
// arrive late, as a slow book's would.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/features/reader/presentation/widgets/custom_epub_viewer.dart';

import 'shared/scroll_view_fixture.dart'
    show expectPageShown, openReader, writeScrollViewEpub;
import 'test_helpers.dart';

const _title = '再構築中の設定変更';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('reader_rebuild_slow_');
    await cleanupAppBooksDir();
  });

  tearDown(() async {
    CustomEpubViewer.debugLoadedDelay = null;
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
    await cleanupAppBooksDir();
  });

  testWidgets('a mode chosen while a new viewer loads is applied once it '
      'loads', (tester) async {
    final controller = await openReader(
      tester,
      await writeScrollViewEpub(tempDir, title: _title, vertical: true),
      _title,
      settings: const ReaderSettings(),
    );
    final viewer = find.byType(CustomEpubViewer);
    final overlay = find.byKey(const Key('reader-loading-overlay'));
    CustomEpubViewer? shown() =>
        tester.widgetList<CustomEpubViewer>(viewer).firstOrNull;
    final notifier = ProviderScope.containerOf(
      tester.element(viewer),
    ).read(readerSettingsProvider.notifier);
    final first = shown()!.key;

    CustomEpubViewer.debugLoadedDelay = const Duration(seconds: 6);
    notifier.setScrollView(true);
    await pumpUntilVisible(tester, overlay);
    final loading = shown()!;
    expect(loading.key, isNot(first));
    expect(loading.scrollView, isTrue);

    // Back to pages while that viewer still loads.
    await tester.pump(const Duration(seconds: 1));
    notifier.setScrollView(false);
    await tester.pump(const Duration(seconds: 1));
    expect(shown()?.key, loading.key, reason: 'left to finish loading');

    // Its late `loaded` (or, failing that, its timeout) brings the next one.
    for (var tick = 0; tick < 120 && shown()?.key == loading.key; tick++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    final next = shown();
    expect(next?.key, isNot(loading.key), reason: 'replaced');
    expect(next?.scrollView, isFalse, reason: 'for pages');
    await pumpUntilGone(tester, overlay, timeout: const Duration(seconds: 30));
    // The reported location arrives a frame after the page shows.
    await tester.pump(const Duration(milliseconds: 1500));
    await expectPageShown(controller, cfi: next!.initialCfi, reason: 'pages');
  });
}
