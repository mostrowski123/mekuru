// The book opens even when the page's `readyToLoad` call never reaches Dart,
// which can happen after an Activity pause/resume: the viewer's onLoadStop
// starts the load instead. That fallback never ran while the viewer compared
// controller wrappers: onLoadStop gets another one than onWebViewCreated.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/presentation/widgets/custom_epub_viewer.dart';

import 'shared/scroll_view_fixture.dart' show openReader, writeScrollViewEpub;
import 'test_helpers.dart';

const _title = '準備信号テスト';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('reader_ready_lost_');
    await cleanupAppBooksDir();
  });

  tearDown(() async {
    CustomEpubViewer.debugDropReadyToLoad = false;
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
    await cleanupAppBooksDir();
  });

  testWidgets('the book opens when the page misses its ready signal', (
    tester,
  ) async {
    CustomEpubViewer.debugDropReadyToLoad = true;

    // Returns once the loading overlay is gone with the viewer still there,
    // which only the viewer's loaded signal does. Without it the reader's
    // 15 s watchdog swaps the viewer for its error screen, and this throws.
    final controller = await openReader(
      tester,
      await writeScrollViewEpub(tempDir, title: _title, vertical: true),
      _title,
      settings: const ReaderSettings(),
    );

    final shown = await evalJson(
      controller,
      'JSON.stringify({start: !!rendition.currentLocation().start})',
    );
    expect(shown['start'], isTrue);
  });
}
