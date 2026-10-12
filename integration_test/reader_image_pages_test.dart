// Image pages fill the screen in paginated view (issue #37). One reader per
// file: see integration_test/shared/scroll_view_fixture.dart.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';

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
    // displayed.total overcounts vertical sections whenever the page height
    // is fractional; expectFillsPage measures the section instead.
    expectFillsPage(await imageState(controller, 'svg'));

    await showSection(tester, controller, 'ornament.xhtml');
    final ornament = await imageState(controller, 'img');
    expect(ornament['w'], closeTo(40, 1), reason: '$ornament');
    expect(ornament['h'], closeTo(20, 1), reason: '$ornament');
    expectCentred(ornament, touching: false);
    expect(ornament['total'], 1, reason: '$ornament');

    await showSection(tester, controller, 'text.xhtml');
    final inline = await imageState(controller, 'img.gaiji');
    expect(inline['inlineStyle'], isEmpty, reason: '$inline');
    expect((inline['w'] as num).toDouble(), lessThanOrEqualTo(128.5));
  });
}
