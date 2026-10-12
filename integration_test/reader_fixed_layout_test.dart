// Fixed-layout (pre-paginated) pages are centred on the screen (issue #37).
// One reader per file: see integration_test/shared/scroll_view_fixture.dart.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/presentation/widgets/custom_epub_controller.dart';

import '../test/shared/epub_fixtures.dart';
import 'shared/image_pages_fixture.dart';
import 'shared/scroll_view_fixture.dart';
import 'test_helpers.dart';

const _title = '漫画テスト';

// The page's scaled box (epub.js scales the body), in the section's
// coordinates.
Future<Map<String, dynamic>> _pageBox(CustomEpubController controller) =>
    evalJson(
      controller,
      '(function () {'
      '  var c = rendition.getContents()[0], L = rendition._layout;'
      '  var r = c.content.getBoundingClientRect();'
      '  return JSON.stringify({W: L.width, H: L.height,'
      '    x: r.left, y: r.top, w: r.width, h: r.height});'
      '})()',
    );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(cleanupAppBooksDir);

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
    await cleanupAppBooksDir();
  });

  testWidgets('portrait and landscape fixed-layout pages are centred', (
    tester,
  ) async {
    final epubPath = await createFixedLayoutMangaEpub(
      pageCount: 2,
      landscapePages: {1},
      prePaginated: true,
    );
    dir = File(epubPath).parent;
    final controller = await openReader(
      tester,
      epubPath,
      _title,
      settings: const ReaderSettings(),
    );

    await showSection(tester, controller, 'page_0.xhtml');
    expectCentred(await _pageBox(controller));

    await showSection(tester, controller, 'page_1.xhtml');
    expectCentred(await _pageBox(controller));
  });
}
