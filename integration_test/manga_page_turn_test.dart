// The Curl page turn in the manga reader on a real GPU: the shader is in the
// app and compiles, the picture of the old page comes up, and the turn ends
// on the next page with the picture gone. No WebView.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/manga/presentation/screens/manga_reader_screen.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/presentation/widgets/reader_page_navigation.dart';
import 'package:path/path.dart' as p;

import 'shared/test_infrastructure.dart';
import 'test_helpers.dart';

const _picture = Key('page-turn-picture');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('manga_page_turn_');
    await cleanupAppBooksDir();
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
    await cleanupAppBooksDir();
  });

  testWidgets('a curl turns a manga page and leaves nothing behind', (
    tester,
  ) async {
    // Test emulators run with system animations off, and that turns page
    // turns off too.
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures();
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    // Without the shader a curl would quietly play as a slide.
    await ui.FragmentProgram.fromAsset('shaders/page_curl.frag');

    final db = createTestDatabase();
    addTearDown(db.close);
    final archive = Archive();
    for (final (index, color) in [
      img.ColorRgb8(200, 30, 30),
      img.ColorRgb8(30, 160, 30),
      img.ColorRgb8(30, 30, 200),
    ].indexed) {
      // A coloured band across the top: a picture drawn upside down shows.
      final page = img.encodePng(
        img.fillRect(
          img.fill(
            img.Image(width: 200, height: 300),
            color: img.ColorRgb8(240, 240, 235),
          ),
          x1: 0,
          y1: 0,
          x2: 199,
          y2: 79,
          color: color,
        ),
      );
      archive.addFile(ArchiveFile('${index + 1}.png', page.length, page));
    }
    final cbz = p.join(tempDir.path, 'pages.cbz');
    await File(cbz).writeAsBytes(ZipEncoder().encode(archive));
    final book = (await BookRepository(db).importCbz(cbz)).book;

    final settings = InMemoryReaderSettingsStorage();
    await settings.save(
      const ReaderSettings(pageTurnStyle: PageTurnStyle.curl),
    );
    await tester.pumpWidget(
      buildIntegrationTestApp(
        db: db,
        home: MangaReaderScreen(book: book),
        readerSettingsStorage: settings,
      ),
    );

    final l10n = await loadExpectedL10n();
    Finder onPage(int page) => find.byWidgetPredicate(
      (w) =>
          w is ReaderPageSemantics &&
          w.label == l10n.readerPageOf(page: page, total: 3),
    );
    await pumpUntilVisible(tester, onPage(1));
    await tester.pump(const Duration(seconds: 1));

    for (final (key, page) in [
      (LogicalKeyboardKey.pageDown, 2),
      (LogicalKeyboardKey.pageDown, 3),
      (LogicalKeyboardKey.pageUp, 2),
    ]) {
      await tester.sendKeyEvent(key);
      await pumpUntilVisible(tester, find.byKey(_picture));
      await pumpUntilGone(tester, find.byKey(_picture));
      expect(onPage(page), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}
