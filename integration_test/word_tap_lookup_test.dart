// Diagnostic/regression test: tapping a word in a real EPUB inside the real
// WebView must produce a wordTapped bridge event and open the lookup sheet.
//
// Captures debugPrint output so the JS console logs ([EPUB_BRIDGE] ...) and
// reader logs ([READER] ...) reveal which layer a tap dies in:
//   no touchDown log        → JS tap listeners never attached / not forwarded
//   touchUp instead of word → getTextAtPoint found no text at the tap point
//   wordTapped but no sheet → Dart side (MeCab / gesture classification)

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/library/presentation/screens/library_screen.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/data/services/mecab_service.dart';
import 'package:mekuru/features/reader/presentation/widgets/custom_epub_viewer.dart';
import 'package:mekuru/features/reader/presentation/widgets/lookup_sheet.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'shared/test_infrastructure.dart';
import 'test_helpers.dart';

Future<String> _writeFixtureEpub(
  Directory dir, {
  bool verticalWithRuby = false,
}) async {
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

  final spineAttrs = verticalWithRuby
      ? ' page-progression-direction="rtl"'
      : '';
  final opfXml =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0">'
      '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:title>タップ本</dc:title>'
      '<dc:language>ja</dc:language>'
      '${verticalWithRuby ? '<meta name="primary-writing-mode" content="vertical-rl"/>' : ''}'
      '</metadata>'
      '<manifest>'
      '<item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>'
      '</manifest>'
      '<spine$spineAttrs><itemref idref="chapter1"/></spine>'
      '</package>';
  final opfBytes = utf8.encode(opfXml);
  archive.addFile(ArchiveFile('OEBPS/content.opf', opfBytes.length, opfBytes));

  // Fill the whole first page with text so a center tap lands on a word.
  // The vertical variant mimics real Japanese novels: vertical-rl writing
  // mode and publisher-supplied <ruby> annotations.
  final body = StringBuffer();
  final paragraph = verticalWithRuby
      ? '<p>今日は<ruby>学校<rt>がっこう</rt></ruby>で'
            '<ruby>日本語<rt>にほんご</rt></ruby>を勉強します。</p>'
      : '<p>今日は学校で日本語を勉強します。</p>';
  for (var i = 0; i < 80; i++) {
    body.write(paragraph);
  }
  final style = verticalWithRuby
      ? '<style>html, body { writing-mode: vertical-rl; }</style>'
      : '';
  final chapterBytes = utf8.encode(
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<html xmlns="http://www.w3.org/1999/xhtml">'
    '<head><title>Chapter 1</title>$style</head>'
    '<body>$body</body>'
    '</html>',
  );
  archive.addFile(
    ArchiveFile('OEBPS/chapter1.xhtml', chapterBytes.length, chapterBytes),
  );

  final epubPath = p.join(dir.path, 'fixture.epub');
  await File(epubPath).writeAsBytes(ZipEncoder().encode(archive));
  return epubPath;
}

/// Non-destructive cleanup: this test may run on a developer's own device,
/// so never wipe the whole books dir — only remove entries the test created.
Future<Set<String>> _snapshotBooksDir() async {
  final appDir = await getApplicationSupportDirectory();
  final booksDir = Directory(p.join(appDir.path, 'books'));
  if (!await booksDir.exists()) return <String>{};
  return booksDir.listSync().map((e) => e.path).toSet();
}

Future<void> _removeNewBooksDirEntries(Set<String> before) async {
  final appDir = await getApplicationSupportDirectory();
  final booksDir = Directory(p.join(appDir.path, 'books'));
  if (!await booksDir.exists()) return;
  for (final entity in booksDir.listSync()) {
    if (!before.contains(entity.path)) {
      try {
        entity.deleteSync(recursive: true);
      } catch (_) {
        // Best-effort; stray fixture folders are orphaned and harmless.
      }
    }
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Set<String> booksDirBefore;
  final capturedLogs = <String>[];
  final originalDebugPrint = debugPrint;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('word_tap_');
    booksDirBefore = await _snapshotBooksDir();
    capturedLogs.clear();
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) capturedLogs.add(message);
      originalDebugPrint(message, wrapWidth: wrapWidth);
    };
  });

  tearDown(() async {
    debugPrint = originalDebugPrint;
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
    await _removeNewBooksDirEntries(booksDirBefore);
  });

  Future<void> runTapScenario(
    WidgetTester tester, {
    required FuriganaMode furiganaMode,
    bool verticalWithRuby = false,
  }) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    await seedDictionaries(db);

    // Real MeCab init on device — same as app startup.
    await MecabService.instance.init();

    final fixturePath = await _writeFixtureEpub(
      tempDir,
      verticalWithRuby: verticalWithRuby,
    );
    await BookRepository(db).importEpub(fixturePath);

    final readerSettings = InMemoryReaderSettingsStorage();
    await readerSettings.save(ReaderSettings(furiganaMode: furiganaMode));

    await tester.pumpWidget(
      buildIntegrationTestApp(
        db: db,
        home: const LibraryScreen(),
        readerSettingsStorage: readerSettings,
      ),
    );
    await pumpUntilVisible(tester, find.text('タップ本'));

    await tester.tap(find.text('タップ本').first);
    await pumpUntilVisible(tester, find.byType(CustomEpubViewer));
    await pumpUntilGone(
      tester,
      find.byKey(const Key('reader-loading-overlay')),
    );

    // Give the section content hook time to attach listeners and render.
    await tester.pump(const Duration(seconds: 2));

    // Tap the center of the viewer where the repeated paragraph text is.
    await tester.tap(find.byType(CustomEpubViewer), warnIfMissed: false);

    // Wait for bridge → Dart → MeCab → sheet.
    var sheetShown = false;
    for (var tick = 0; tick < 40; tick++) {
      await tester.pump(const Duration(milliseconds: 250));
      if (find.byType(LookupSheet).evaluate().isNotEmpty) {
        sheetShown = true;
        break;
      }
    }

    // Diagnostics: surface the relevant log lines regardless of outcome.
    final relevant = capturedLogs
        .where(
          (l) =>
              l.contains('EPUB_BRIDGE') ||
              l.contains('EPUB_JS') ||
              l.contains('[READER]') ||
              l.contains('EPUB display error') ||
              l.contains('[MeCab]'),
        )
        .toList();
    // ignore: avoid_print
    print('=== DIAGNOSTIC LOGS (${relevant.length}) ===');
    for (final line in relevant) {
      // ignore: avoid_print
      print('  $line');
    }

    expect(
      sheetShown,
      isTrue,
      reason:
          'Lookup sheet did not appear after tapping text '
          '(furiganaMode=$furiganaMode). '
          'Diagnostic logs above show where the tap died.',
    );
  }

  testWidgets('tapping text opens the lookup sheet (furigana off)', (
    tester,
  ) async {
    await runTapScenario(tester, furiganaMode: FuriganaMode.off);
  });

  testWidgets('tapping text opens the lookup sheet (furigana on)', (
    tester,
  ) async {
    await runTapScenario(tester, furiganaMode: FuriganaMode.all);
  });

  testWidgets(
    'tapping text opens the lookup sheet (vertical-rl book with ruby)',
    (tester) async {
      await runTapScenario(
        tester,
        furiganaMode: FuriganaMode.off,
        verticalWithRuby: true,
      );
    },
  );
}
