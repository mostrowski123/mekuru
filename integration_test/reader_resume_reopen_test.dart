// Regression test for the spinner-hang bug:
//   cold-start app → open book → back to library → background/foreground →
//   open same book → spinner used to spin forever.
//
// The actual native-WebView race only fires on a real device or emulator
// (where Activity pause/resume tears down WebView state). This widget-level
// test still locks in the Dart-side contract: a fresh InAppWebView mount
// after `AppLifecycleState.paused → resumed` must load and dismiss the
// spinner within the watchdog window. If a future refactor reintroduces a
// reliance on the JS-initiated `readyToLoad` handshake without an
// `onLoadStop` fallback or watchdog, this test will surface it.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/library/presentation/screens/library_screen.dart';
import 'package:mekuru/features/reader/presentation/widgets/custom_epub_viewer.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'shared/test_infrastructure.dart';
import 'test_helpers.dart';

Future<String> _writeFixtureEpub(Directory dir, {required String title}) async {
  final archive = Archive();

  final containerXml =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
      '<rootfiles>'
      '<rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>'
      '</rootfiles>'
      '</container>';
  final containerBytes = utf8.encode(containerXml);
  archive.addFile(
    ArchiveFile(
      'META-INF/container.xml',
      containerBytes.length,
      containerBytes,
    ),
  );

  final opfXml =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0">'
      '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:title>$title</dc:title>'
      '<dc:language>ja</dc:language>'
      '</metadata>'
      '<manifest>'
      '<item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>'
      '</manifest>'
      '<spine><itemref idref="chapter1"/></spine>'
      '</package>';
  final opfBytes = utf8.encode(opfXml);
  archive.addFile(
    ArchiveFile('OEBPS/content.opf', opfBytes.length, opfBytes),
  );

  final chapterBytes = utf8.encode(
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<html xmlns="http://www.w3.org/1999/xhtml">'
    '<head><title>Chapter 1</title></head>'
    '<body><p>テスト。</p></body>'
    '</html>',
  );
  archive.addFile(
    ArchiveFile(
      'OEBPS/chapter1.xhtml',
      chapterBytes.length,
      chapterBytes,
    ),
  );

  final epubPath = p.join(dir.path, 'fixture.epub');
  await File(epubPath).writeAsBytes(ZipEncoder().encode(archive));
  return epubPath;
}

Future<void> _cleanupAppBooksDir() async {
  final appDir = await getApplicationSupportDirectory();
  final booksDir = Directory(p.join(appDir.path, 'books'));
  if (await booksDir.exists()) {
    await booksDir.delete(recursive: true);
  }
}

Future<void> pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
  Duration step = const Duration(milliseconds: 250),
}) async {
  final maxTicks = timeout.inMilliseconds ~/ step.inMilliseconds;
  for (var tick = 0; tick < maxTicks; tick++) {
    await tester.pump(step);
    if (finder.evaluate().isEmpty) return;
  }
  throw TestFailure('Timed out waiting for $finder to disappear after $timeout.');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('reader_resume_');
    await _cleanupAppBooksDir();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
    await _cleanupAppBooksDir();
  });

  testWidgets(
    'reader spinner resolves on second open after app background/resume',
    (tester) async {
      final db = createTestDatabase();
      addTearDown(db.close);

      final fixturePath = await _writeFixtureEpub(tempDir, title: 'テストの本');
      await BookRepository(db).importEpub(fixturePath);

      await tester.pumpWidget(
        buildIntegrationTestApp(db: db, home: const LibraryScreen()),
      );
      await pumpUntilVisible(tester, find.text('テストの本'));

      // First open — sanity baseline.
      await tester.tap(find.text('テストの本').first);
      await pumpUntilVisible(tester, find.byType(CustomEpubViewer));
      await pumpUntilGone(
        tester,
        find.byKey(const Key('reader-loading-overlay')),
        timeout: const Duration(seconds: 20),
      );

      // Back to library.
      await tester.pageBack();
      await pumpUntilVisible(tester, find.text('テストの本'));

      // Background → foreground via the lifecycle channel, matching the
      // sequence Android dispatches when the user taps home then re-launches.
      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(milliseconds: 200));
      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 200));

      // Second open — the regression we're locking down.
      await tester.tap(find.text('テストの本').first);
      await pumpUntilVisible(tester, find.byType(CustomEpubViewer));
      await pumpUntilGone(
        tester,
        find.byKey(const Key('reader-loading-overlay')),
        timeout: const Duration(seconds: 18),
      );
    },
  );
}
