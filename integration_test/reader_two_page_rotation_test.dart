// Turning the screen with "Two pages on wide screens" on: upright shows one
// page, sideways two, and the first character on screen stays on screen
// through every switch. A rotation lays the book out once, as it does with
// the switch off: the switch to two pages rides on that pass. Switching it
// off while sideways goes back to one page at the same place.
// One reader per file: see integration_test/shared/scroll_view_fixture.dart.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/features/reader/presentation/screens/reader_screen.dart';
import 'package:mekuru/features/reader/presentation/widgets/custom_epub_controller.dart';

import 'shared/scroll_view_fixture.dart';
import 'shared/two_page_fixture.dart';
import 'test_helpers.dart';

const _title = '回転見開きテスト';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('reader_two_page_turn_');
    await cleanupAppBooksDir();
  });

  tearDown(() async {
    await SystemChrome.setPreferredOrientations([]);
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
    await cleanupAppBooksDir();
  });

  testWidgets('rotating switches between one and two pages in place', (
    tester,
  ) async {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await tester.pump(const Duration(seconds: 2));

    final controller = await openReader(
      tester,
      await writeScrollViewEpub(tempDir, title: _title, vertical: true),
      _title,
      settings: const ReaderSettings(epubTwoPage: true),
    );

    // Upright: one page. Read on a few pages.
    expect((await settledPairState(tester, controller))['divisor'], 1);
    for (var turns = 0; turns < 3; turns++) {
      controller.next();
      await tester.pump(const Duration(milliseconds: 900));
    }
    final upright = await settledPairState(tester, controller);
    expect(upright['index'], 0, reason: '$upright');
    final first = upright['cfi'] as String;

    Future<Map<String, dynamic>> turnScreen(DeviceOrientation to) async {
      await _countLayouts(controller);
      await SystemChrome.setPreferredOrientations([to]);
      await tester.pump(const Duration(seconds: 2));
      final state = await settledPairState(tester, controller);
      final shown = await charShown(controller, first);
      return {
        ...state,
        'shown': shown['shown'],
        'x': shown['x'],
        'first': first,
        'layouts': await _layouts(controller),
      };
    }

    // Sideways: two pages, the character still on screen.
    final sideways = await turnScreen(DeviceOrientation.landscapeLeft);
    expect(
      [sideways['divisor'], sideways['shown']],
      [2, true],
      reason: '$sideways',
    );

    // Upright again: one page, same character.
    final back = await turnScreen(DeviceOrientation.portraitUp);
    expect([back['divisor'], back['shown']], [1, true], reason: '$back');

    // Sideways, then the switch off: one page, same character.
    final again = await turnScreen(DeviceOrientation.landscapeLeft);
    expect([again['divisor'], again['shown']], [2, true], reason: '$again');
    await _countLayouts(controller);
    ProviderScope.containerOf(
      tester.element(find.byType(ReaderScreen)),
    ).read(readerSettingsProvider.notifier).setEpubTwoPage(false);
    await tester.pump(const Duration(seconds: 2));
    final off = await settledPairState(tester, controller);
    expect(off['divisor'], 1, reason: '$off');
    expect((await charShown(controller, first))['shown'], isTrue);
    expect(await _layouts(controller), 1, reason: 'the switch lays out once');

    // A rotation with the switch off, for comparison: the rotations above
    // laid the book out no more often.
    final plain = await turnScreen(DeviceOrientation.portraitUp);
    expect(plain['shown'], isTrue, reason: '$plain');
    for (final turned in [sideways, back, again]) {
      expect(
        turned['layouts'],
        lessThanOrEqualTo(plain['layouts'] as int),
        reason: 'with the switch off: $plain, on: $turned',
      );
    }
  });
}

// Counts the section views epub.js makes from now on: one per lay-out.
Future<void> _countLayouts(CustomEpubController controller) =>
    controller.debugEvaluateJavascript('''
(function () {
  var m = rendition.manager;
  window._layoutCount = 0;
  if (!m._countingViews) {
    var make = m.createView;
    m.createView = function () {
      window._layoutCount++;
      return make.apply(m, arguments);
    };
    m._countingViews = true;
  }
  return true;
})()
''');

Future<int> _layouts(CustomEpubController controller) async =>
    (await evalJson(
          controller,
          'JSON.stringify({n: window._layoutCount})',
        ))['n']
        as int;
