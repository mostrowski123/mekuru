// Image pages fill the screen in paginated view (issue #37). One reader per
// file: see integration_test/shared/scroll_view_fixture.dart.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/presentation/widgets/custom_epub_viewer.dart';
import 'package:mekuru/features/reader/presentation/widgets/epub_image_zoom_view.dart';
import 'package:mekuru/shared/widgets/reader_seek_bar.dart';

import 'shared/image_pages_fixture.dart';
import 'shared/scroll_view_fixture.dart';
import 'test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('reader_image_pages_');
    await cleanupAppBooksDir();
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
    await cleanupAppBooksDir();
  });

  testWidgets('image pages fill the page and text pages are untouched', (
    tester,
  ) async {
    final controller = await openReader(
      tester,
      await writeImagePagesEpub(tempDir),
      imagePagesTitle,
      settings: const ReaderSettings(),
    );

    await showSection(tester, controller, 'portrait.xhtml');
    final portrait = await imageState(controller, 'img');
    expectFillsPage(portrait);
    expect(portrait['fit'], 'contain', reason: '$portrait');
    expect(portrait['position'], '50% 50%', reason: '$portrait');
    expect(portrait['total'], 1, reason: '$portrait');
    // The book asks for two-up pages; the reader turns one page at a time.
    expect(portrait['spread'], isFalse, reason: '$portrait');

    await showSection(tester, controller, 'spread.xhtml');
    final spread = await imageState(controller, 'svg');
    expectFillsPage(spread);
    // Nothing on an image page is text: no selection loupe while a finger
    // is held on it (iOS).
    expect(spread['bodySelect'], 'none', reason: '$spread');
    // One page, also when the page height is fractional (here with margins).
    expect(spread['total'], 1, reason: '$spread');

    await showSection(tester, controller, 'ornament.xhtml');
    final ornament = await imageState(controller, 'img');
    expectSmallAndCentred(ornament);
    expect(ornament['total'], 1, reason: '$ornament');
    // Under 64 px: no zoom.
    expect(await zoomableAtCentre(controller), isFalse);

    // The same ornament straight in a vertical page's body.
    await showSection(tester, controller, 'bare.xhtml');
    expectSmallAndCentred(await imageState(controller, 'img'));

    await showSection(tester, controller, 'text.xhtml');
    final inline = await imageState(controller, 'img.gaiji');
    expect(inline['inlineStyle'], isEmpty, reason: '$inline');
    expect(inline['bodySelect'], isNot('none'), reason: '$inline');
    expect((inline['w'] as num).toDouble(), lessThanOrEqualTo(128.5));

    // A linked illustration keeps its size: taps beside it turn the page.
    await showSection(tester, controller, 'linked.xhtml');
    final linked = await imageState(controller, 'img');
    expect(linked['inlineStyle'], isEmpty, reason: '$linked');

    // Closes the zoom viewer: the controls stay hidden behind it.
    Future<void> closeZoom() async {
      await tester.tap(find.byType(EpubImageZoomView));
      await pumpUntilGone(tester, find.byType(EpubImageZoomView));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(ReaderBarScrim), findsNothing);
    }

    // A real finger: synthetic touches reach the WebView as real touches
    // on Android only (see integration_test_webview_tap_limitations).
    if (Platform.isAndroid) {
      Future<void> hold() async {
        await controller.debugEvaluateJavascript(
          'window._touches = 0;'
          'rendition.getContents()[0].document.addEventListener('
          '"touchstart", function () { window._touches++; }); true',
        );
        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(CustomEpubViewer)),
        );
        await tester.pump(const Duration(milliseconds: 800));
        await gesture.up();
        await tester.pump(const Duration(seconds: 1));
        expect(
          await controller.debugEvaluateJavascript('window._touches'),
          1,
          reason: 'the press should reach the page',
        );
      }

      // On text nothing opens.
      await showSection(tester, controller, 'text.xhtml');
      await hold();
      expect(find.byType(EpubImageZoomView), findsNothing);
      // The hold selected a word: let it go, as a tap beside it would.
      await controller.debugEvaluateJavascript('clearSelection(); true');

      await showSection(tester, controller, 'spread.xhtml');
      await hold();
      await pumpUntilVisible(tester, find.byType(EpubImageZoomView));
      await closeZoom();

      // A double tap opens it too, and leaves the controls hidden.
      final centre = tester.getCenter(find.byType(CustomEpubViewer));
      await tester.tapAt(centre);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(centre);
      await pumpUntilVisible(tester, find.byType(EpubImageZoomView));
      await closeZoom();

      // A single tap in the middle shows the controls instead.
      await tester.tapAt(centre);
      await pumpUntilVisible(tester, find.byType(ReaderBarScrim));
      expect(find.byType(EpubImageZoomView), findsNothing);
      await tester.tapAt(centre);
      await pumpUntilGone(tester, find.byType(ReaderBarScrim));
    }

    // The bridge's long press, as on iOS where synthetic touches never reach
    // the WebView: the image opens full screen, and a tap closes it.
    await showSection(tester, controller, 'spread.xhtml');
    await longPressImage(controller, 'svg image');
    await pumpUntilVisible(tester, find.byType(EpubImageZoomView));
    expect(zoomedFiles(tester), ['wide.png']);
    await closeZoom();

    // The bridge's taps: a double tap opens the image...
    await tapImage(controller, 'svg image', taps: 2);
    await pumpUntilVisible(tester, find.byType(EpubImageZoomView));
    expect(zoomedFiles(tester), ['wide.png']);
    await closeZoom();

    // ...and a single tap shows the controls once no second tap follows.
    await tapImage(controller, 'svg image');
    await pumpUntilVisible(tester, find.byType(ReaderBarScrim));
    expect(find.byType(EpubImageZoomView), findsNothing);
  });
}
