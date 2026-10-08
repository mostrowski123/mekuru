// Changing the font size or the margins re-lays the book out at the current
// page. In vertical text epub.js placed the page with a stale step (the
// column width instead of the page height) whenever the section was already
// on screen, so a quick run of changes, such as dragging the font size
// slider, left the page cut in half until the book was reopened.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/features/reader/presentation/widgets/custom_epub_controller.dart';
import 'package:mekuru/features/reader/presentation/widgets/custom_epub_viewer.dart';

import 'shared/scroll_view_fixture.dart';
import 'test_helpers.dart';

const _title = '再レイアウトテスト';

// How far the view is from the nearest page boundary, in pixels. Page turns
// scroll by the container's own size (see snapToNearestPage in the bridge).
const _offPage =
    '(function () {'
    '  var m = rendition.manager, c = m.container;'
    '  var vertical = m.settings.axis === "vertical";'
    '  var step = vertical ? c.offsetHeight : c.offsetWidth;'
    '  var pos = Math.abs(vertical ? c.scrollTop : c.scrollLeft);'
    '  var off = pos % step;'
    '  return JSON.stringify({pos: pos, step: step,'
    '    cfi: rendition.location.start.cfi,'
    '    off: Math.min(off, step - off)});'
    '})()';

Future<Map<String, dynamic>> _expectWholePage(
  CustomEpubController controller,
  String when,
) async {
  final state = await evalJson(controller, _offPage);
  expect(
    (state['off'] as num).toDouble(),
    lessThan(1),
    reason: 'view between two pages $when: $state',
  );
  return state;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('reader_relayout_');
    await cleanupAppBooksDir();
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
    await cleanupAppBooksDir();
  });

  testWidgets('font size and margin changes keep the page whole', (
    tester,
  ) async {
    final controller = await openReader(
      tester,
      await writeScrollViewEpub(tempDir, title: _title, vertical: true),
      _title,
      settings: const ReaderSettings(),
    );
    final settings = ProviderScope.containerOf(
      tester.element(find.byType(CustomEpubViewer)),
    ).read(readerSettingsProvider.notifier);
    const settle = Duration(seconds: 3);

    // Off the first page, where every offset is trivially a boundary.
    for (var i = 0; i < 3; i++) {
      controller.next();
      await tester.pump(const Duration(milliseconds: 600));
    }
    final start = await _expectWholePage(controller, 'after turning pages');
    expect((start['pos'] as num).toDouble(), greaterThan(0));

    for (final size in [24.0, 30.0, 15.0]) {
      settings.setFontSize(size);
      await tester.pump(settle);
      await _expectWholePage(controller, 'after font size $size');
    }

    settings.setHorizontalPadding(48);
    await tester.pump(settle);
    await _expectWholePage(controller, 'after a margin change');

    // A slider drag sends a change per tick, faster than a re-layout.
    for (final size in [16.0, 17.0, 18.0, 19.0, 20.0]) {
      settings.setFontSize(size);
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(settle);
    final dragged = await _expectWholePage(controller, 'after a slider drag');

    // A jump to the page already shown (a bookmark on it) stays on it.
    controller.display(cfi: dragged['cfi'] as String);
    await tester.pump(settle);
    final jumped = await _expectWholePage(controller, 'after a jump');
    expect(jumped['pos'], dragged['pos']);
  });
}
