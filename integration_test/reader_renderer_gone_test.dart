// The reader survives its WebView's renderer dying, which Android does to a
// background app's renderer when memory runs low: without
// useOnRenderProcessGone the whole app went down with it. A new viewer opens
// at the page the reader showed. chrome://crash stands in for the kill, so
// this runs on Android only (a test cannot end WKWebView's content process).

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/presentation/widgets/custom_epub_viewer.dart';

import 'shared/scroll_view_fixture.dart' show openReader, writeScrollViewEpub;
import 'test_helpers.dart';

const _title = 'レンダラーテスト';

void main() {
  // Every frame drawn, as in the app. Under the default policy only pumps
  // draw, so the new viewer's web view stays unsized while it loads the
  // book, and the book loses its page at the first resize.
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('reader_renderer_gone_');
    await cleanupAppBooksDir();
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
    await cleanupAppBooksDir();
  });

  testWidgets('the reader comes back at its page when the renderer dies', (
    tester,
  ) async {
    final controller = await openReader(
      tester,
      await writeScrollViewEpub(tempDir, title: _title, vertical: true),
      _title,
      settings: const ReaderSettings(),
    );
    Future<String?> shownCfi() async =>
        (await evalJson(
              controller,
              'JSON.stringify({cfi: rendition.currentLocation().start'
              ' ? rendition.currentLocation().start.cfi : null})',
            ))['cfi']
            as String?;

    // Off the first page, so a viewer opening at the start fails the test.
    final first = await shownCfi();
    controller.next();
    var shown = first;
    for (var tick = 0; tick < 40 && shown == first; tick++) {
      await tester.pump(const Duration(milliseconds: 100));
      shown = await shownCfi();
    }
    expect(shown, isNot(first));
    // Let the reader take in the relocation.
    await tester.pump(const Duration(milliseconds: 500));

    Key? viewerKey() =>
        tester.widget<CustomEpubViewer>(find.byType(CustomEpubViewer)).key;
    final deadViewer = viewerKey();
    await controller.debugCrashRenderer();
    for (var tick = 0; tick < 100 && viewerKey() == deadViewer; tick++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(viewerKey(), isNot(deadViewer), reason: 'no new viewer');
    await pumpUntilGone(
      tester,
      find.byKey(const Key('reader-loading-overlay')),
      timeout: const Duration(seconds: 20),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(await shownCfi(), shown);
  }, skip: defaultTargetPlatform != TargetPlatform.android);
}
