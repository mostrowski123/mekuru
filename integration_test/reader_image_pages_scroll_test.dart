// Image pages fill exactly one screen in scroll view (issue #37). One reader
// per file: see integration_test/shared/scroll_view_fixture.dart.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'shared/image_pages_fixture.dart';
import 'shared/scroll_view_fixture.dart';
import 'test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('reader_image_scroll_');
    await cleanupAppBooksDir();
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
    await cleanupAppBooksDir();
  });

  testWidgets('an image section is exactly one screen', (tester) async {
    final controller = await openReader(
      tester,
      await writeImagePagesEpub(tempDir),
      imagePagesTitle,
    );

    for (final (href, selector) in [
      ('portrait.xhtml', 'img'),
      ('spread.xhtml', 'svg'),
    ]) {
      await showSection(tester, controller, href);
      expectFillsPage(await imageState(controller, selector));
    }
  });
}
