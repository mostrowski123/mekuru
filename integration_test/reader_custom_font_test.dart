// A font the user added reaches the reader: the chapter text names its
// family and lays out with its glyphs, it survives a colour change and a
// viewer rebuild, the last of two quick choices wins, and going back to
// the book's fonts drops it.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/data/services/user_font_store.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/features/reader/presentation/widgets/custom_epub_viewer.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'shared/scroll_view_fixture.dart';
import 'shared/test_fonts.dart';
import 'test_helpers.dart';

const _title = 'フォント追加テスト';

// The paragraph's font family, and how wide 山 is in em when laid out
// horizontally in the chapter (a throwaway span, out of the page flow).
const _probe =
    '(function () {'
    '  var doc = rendition.getContents()[0].document;'
    '  var win = doc.defaultView;'
    '  var para = doc.querySelector("p");'
    '  var s = doc.createElement("span");'
    '  s.textContent = "山";'
    '  s.style.cssText = "position:absolute;writing-mode:horizontal-tb;'
    'white-space:nowrap;";'
    '  doc.body.appendChild(s);'
    '  var em = s.getBoundingClientRect().width /'
    '    parseFloat(win.getComputedStyle(s).fontSize);'
    '  s.remove();'
    '  return JSON.stringify({family: win.getComputedStyle(para).fontFamily,'
    '    em: em});'
    '})()';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory fontsDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('reader_custom_font_');
    fontsDir = Directory(
      p.join(
        (await getApplicationSupportDirectory()).path,
        UserFontStore.dirName,
      ),
    );
    if (await fontsDir.exists()) await fontsDir.delete(recursive: true);
    await cleanupAppBooksDir();
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
    if (await fontsDir.exists()) await fontsDir.delete(recursive: true);
    await cleanupAppBooksDir();
  });

  testWidgets('an added font is used, kept and dropped as chosen', (
    tester,
  ) async {
    Future<String> add(String name, List<int> bytes) async {
      final file = File(p.join(tempDir.path, name))
        ..writeAsBytesSync(Uint8List.fromList(bytes));
      return (await UserFontStore().import(file.path)).fileName;
    }

    final wide = await add('Wide.ttf', testFontWide);
    final wider = await add('Wider.ttf', testFontWider);

    final controller = await openReader(
      tester,
      await writeScrollViewEpub(tempDir, title: _title, vertical: true),
      _title,
      settings: ReaderSettings(
        fontFamily: ReaderFontFamily.custom,
        customFontFile: wide,
      ),
    );
    final settings = ProviderScope.containerOf(
      tester.element(find.byType(CustomEpubViewer)),
    ).read(readerSettingsProvider.notifier);
    const settle = Duration(seconds: 3);

    Future<void> expectFont(double em, String when) async {
      final probe = await evalJson(controller, _probe);
      expect(probe['family'], contains('mekuru-user-font-'), reason: when);
      expect((probe['em'] as num).toDouble(), closeTo(em, 0.05), reason: when);
    }

    await expectFont(2, 'on opening');

    // The theme is rebuilt from settings on a colour change; it must still
    // name the added font.
    settings.setColorMode(ColorMode.sepia);
    await tester.pump(settle);
    await expectFont(2, 'after a colour change');

    // The second of two quick choices wins.
    settings.setCustomFont(wider);
    settings.setCustomFont(wide);
    await tester.pump(settle);
    await expectFont(2, 'after two quick choices');

    settings.setCustomFont(wider);
    await tester.pump(settle);
    await expectFont(3, 'after switching fonts');

    settings.setFontFamily(ReaderFontFamily.book);
    await tester.pump(settle);
    final probe = await evalJson(controller, _probe);
    expect(probe['family'], isNot(contains('mekuru-user-font-')));

    // A viewer rebuild makes a new WebView, which must be sent the font
    // again before its book loads. A second WebView in one test process
    // renders blank (see the integration-test WebView notes), so this reads
    // the bridge's font state there instead of measuring glyphs.
    settings.setCustomFont(wider);
    await tester.pump(settle);
    final oldViewer = find.byKey(
      tester.widget<CustomEpubViewer>(find.byType(CustomEpubViewer)).key!,
    );
    settings.setVerticalText(false);
    await pumpUntilGone(
      tester,
      oldViewer,
      timeout: const Duration(seconds: 20),
    );
    await pumpUntilGone(
      tester,
      find.byKey(const Key('reader-loading-overlay')),
      timeout: const Duration(seconds: 20),
    );
    final sent = await evalJson(
      controller,
      '(function () { return JSON.stringify({family: _userFontFamily,'
      ' bytes: _userFontBuf ? _userFontBuf.length : 0,'
      ' loaded: typeof rendition !== "undefined"}); })()',
    );
    expect(sent['family'], startsWith('mekuru-user-font-'));
    expect(sent['bytes'], testFontWider.length);
    expect(sent['loaded'], isTrue);
  });
}
