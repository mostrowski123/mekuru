// Going back a chapter jumps to the chapter's last page. With the screen
// sideways a vertical page is shorter than it is wide, and once the chapter
// had settled the jump stepped by the width instead of the page height: it
// stopped part-way down a page, short of the last one. One reader per file:
// see integration_test/shared/scroll_view_fixture.dart.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';

import 'shared/scroll_view_fixture.dart';
import 'test_helpers.dart';

const _title = '横向きテスト';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('reader_landscape_');
    await cleanupAppBooksDir();
  });

  tearDown(() async {
    await SystemChrome.setPreferredOrientations([]);
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
    await cleanupAppBooksDir();
  });

  testWidgets('the last page of a vertical chapter is found sideways', (
    tester,
  ) async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
    ]);
    await tester.pump(const Duration(seconds: 2));

    final controller = await openReader(
      tester,
      await writeScrollViewEpub(tempDir, title: _title, vertical: true),
      _title,
      settings: const ReaderSettings(),
    );
    // Settled: epub.js has put its page step back to the column width.
    await tester.pump(const Duration(seconds: 2));

    await controller.debugEvaluateJavascript("snapToLastPage('test'); true");
    await tester.pump(const Duration(seconds: 1));

    final at = await evalJson(
      controller,
      '(function () {'
      '  var c = rendition.manager.container;'
      '  return JSON.stringify({top: Math.round(c.scrollTop),'
      '    end: c.scrollHeight - c.offsetHeight,'
      '    pages: c.scrollHeight / c.offsetHeight,'
      '    wide: c.offsetWidth > c.offsetHeight});'
      '})()',
    );
    expect(at['wide'], isTrue, reason: 'needs a page wider than it is tall');
    expect(at['pages'], greaterThan(2), reason: 'needs a few pages: $at');
    expect(at['top'], at['end'], reason: '$at');
  });
}
