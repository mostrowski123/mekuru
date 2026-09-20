// Not a test of behaviour: a scripted tour that puts the app into the states
// the App Store screenshots show. At each stop it prints `@@SHOT <name>` and
// holds still for a few seconds; tools/app_store_screenshots.sh watches the
// log and captures the simulator's screen. All content is public domain
// (Natsume Soseki, Dazai Osamu, Miyazawa Kenji) or written here.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/library/presentation/screens/library_screen.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/data/services/mecab_service.dart';
import 'package:mekuru/features/reader/presentation/widgets/custom_epub_viewer.dart';
import 'package:mekuru/features/reader/presentation/widgets/lookup_sheet.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'shared/screenshot_seed.dart';
import 'shared/test_infrastructure.dart';
import 'test_helpers.dart';

void main() {
  // The word is tapped with a real touch on the simulator; by default the
  // test binding swallows device touches while a test runs.
  IntegrationTestWidgetsFlutterBinding.ensureInitialized()
          .shouldPropagateDevicePointerEvents =
      true;

  testWidgets('App Store screenshot tour', (tester) async {
    // The test harness builds its own MaterialApp, which would show the
    // debug banner in every screenshot.
    WidgetsApp.debugAllowBannerOverride = false;
    Future<void> shot(String name) async {
      // ignore: avoid_print
      print('@@SHOT $name');
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
    }

    final db = createTestDatabase();
    addTearDown(db.close);
    await MecabService.instance.init();

    final temp = await Directory(
      p.join((await getTemporaryDirectory()).path, 'shots'),
    ).create(recursive: true);
    // Only what this run imports is removed afterwards: the simulator may
    // hold a library from manual testing.
    final booksDir = await appBooksDir();
    final before = booksDir.existsSync()
        ? booksDir.listSync().map((e) => e.path).toSet()
        : <String>{};
    addTearDown(() async {
      await temp.delete(recursive: true);
      if (!booksDir.existsSync()) return;
      for (final entry in booksDir.listSync()) {
        if (!before.contains(entry.path)) await entry.delete(recursive: true);
      }
    });
    await seedScreenshotLibrary(db, temp, offUiThread: tester.runAsync);

    final readerSettings = InMemoryReaderSettingsStorage();
    await readerSettings.save(
      const ReaderSettings(furiganaMode: FuriganaMode.hide),
    );
    await tester.pumpWidget(
      buildIntegrationTestApp(
        db: db,
        home: const LibraryScreen(),
        readerSettingsStorage: readerSettings,
      ),
    );
    await pumpUntilVisible(tester, find.text(screenshotBooks.first.$1));
    await shot('01-library');

    await tester.tap(find.text(screenshotBooks.first.$1).first);
    await pumpUntilVisible(tester, find.byType(CustomEpubViewer));
    await pumpUntilGone(
      tester,
      find.byKey(const Key('reader-loading-overlay')),
    );
    await tester.pump(const Duration(seconds: 3));
    await shot('02-reader');

    // A synthetic tester tap does not reach the WKWebView on iOS, so the word
    // is tapped from outside (a real touch on the simulator) while this waits.
    // ignore: avoid_print
    print('@@WAITTAP');
    var found = false;
    for (var tick = 0; tick < 160 && !found; tick++) {
      await tester.pump(const Duration(milliseconds: 250));
      found = find.byType(LookupSheet).evaluate().isNotEmpty;
    }
    if (!found) {
      // The library and reader shots are still good; say so and stop.
      // ignore: avoid_print
      print('@@NOTE no lookup sheet appeared, skipping 03-lookup');
      return;
    }
    await tester.pump(const Duration(seconds: 2));
    await shot('03-lookup');
  });
}
