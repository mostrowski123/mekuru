import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/library/data/services/epub_furigana_export.dart';
import 'package:mekuru/features/library/presentation/screens/library_screen.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/data/services/mecab_service.dart';

import 'shared/test_infrastructure.dart';
import 'test_helpers.dart';

/// Integration test for the furigana EPUB export pipeline.
///
/// Unit tests cover the XHTML rewriting with a fake tokenizer; this test
/// exercises the real path used by the export action on device: MeCab init →
/// MecabService.runOffIsolate worker → buildFuriganaEpubForMode → zip out.
const _containerXml =
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<container version="1.0" '
    'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
    '<rootfiles><rootfile full-path="OEBPS/content.opf" '
    'media-type="application/oebps-package+xml"/></rootfiles></container>';

const _contentOpf =
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
    'unique-identifier="id">'
    '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
    '<dc:title>再輸入の本</dc:title>'
    '<dc:language>ja</dc:language>'
    '</metadata>'
    '<manifest>'
    '<item id="c1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>'
    '</manifest>'
    '<spine><itemref idref="c1"/></spine></package>';

String _chapter(String body) =>
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<!DOCTYPE html>\n'
    '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>t</title></head>'
    '<body>$body</body></html>';

Uint8List _buildEpub(String chapterXhtml) {
  final archive = Archive()
    ..addFile(
      ArchiveFile.noCompress(
        'mimetype',
        20,
        utf8.encode('application/epub+zip'),
      ),
    )
    ..addFile(
      ArchiveFile.bytes('META-INF/container.xml', utf8.encode(_containerXml)),
    )
    ..addFile(ArchiveFile.bytes('OEBPS/content.opf', utf8.encode(_contentOpf)))
    ..addFile(
      ArchiveFile.bytes('OEBPS/chapter1.xhtml', utf8.encode(chapterXhtml)),
    );
  return ZipEncoder().encodeBytes(archive);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await MecabService.instance.init();
  });

  Future<String> writeEpub(String body) async {
    final tempDir = await Directory.systemTemp.createTemp('export_flow_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final path = '${tempDir.path}/book.epub';
    await File(path).writeAsBytes(_buildEpub(_chapter(body)));
    return path;
  }

  String chapterOut(Uint8List epubBytes) {
    final decoded = ZipDecoder().decodeBytes(epubBytes);
    expect(decoded.files.first.name, 'mimetype');
    expect(decoded.files.first.compression, CompressionType.none);
    return utf8.decode(decoded.findFile('OEBPS/chapter1.xhtml')!.readBytes()!);
  }

  test('mode all annotates via the runOffIsolate worker', () async {
    final path = await writeEpub('<p>今日は晴れだ。</p>');

    final bytes = await MecabService.instance.runOffIsolate(
      () =>
          buildFuriganaEpubForMode(path, mode: FuriganaMode.all, jlptLevel: 3),
    );

    expect(bytes, isNotNull);
    final xhtml = chapterOut(bytes!);
    expect(xhtml, contains('<ruby>今日<rt>きょう</rt></ruby>'));
    expect(xhtml, contains('<rt>'));
  });

  test('mode aboveLevel keeps easy words bare, annotates hard ones', () async {
    final path = await writeEpub('<p>今日は憂鬱だ。</p>');

    final bytes = await MecabService.instance.runOffIsolate(
      () => buildFuriganaEpubForMode(
        path,
        mode: FuriganaMode.aboveLevel,
        jlptLevel: 3,
      ),
    );

    expect(bytes, isNotNull);
    final xhtml = chapterOut(bytes!);
    // 憂 is N1 → the whole word gets ruby; 今日 is N5 kanji → stays bare.
    expect(xhtml, contains('<ruby>憂鬱<rt>ゆううつ</rt></ruby>'));
    expect(xhtml, isNot(contains('<ruby>今日')));
    expect(xhtml, contains('今日'));
  });

  // Regression: JLPT-mode exports used to corrupt META-INF/container.xml and
  // the OPF (the exporter read them to find the manifest, then passed the
  // consumed zip entries through to the encoder, which double-deflated
  // them), so the exported book could never be imported again.
  test('JLPT export reimports cleanly with metadata and ruby intact', () async {
    final path = await writeEpub('<p>今日は憂鬱だ。</p>');

    final bytes = await MecabService.instance.runOffIsolate(
      () => buildFuriganaEpubForMode(
        path,
        mode: FuriganaMode.aboveLevel,
        jlptLevel: 3,
      ),
    );
    expect(bytes, isNotNull);

    // writeEpub's temp dir already has a recursive-delete teardown; the
    // exported copy can live next to the source.
    addTearDown(cleanupAppBooksDir);
    final exportedPath = '${File(path).parent.path}/exported (furigana).epub';
    await File(exportedPath).writeAsBytes(bytes!);

    final db = createTestDatabase();
    addTearDown(db.close);
    final imported = await BookRepository(db).importEpub(exportedPath);

    // Title and language only survive if the OPF round-tripped intact.
    expect(imported.title, '再輸入の本');
    expect(imported.language, 'ja');

    // And the annotated chapter must be what the reader actually loads.
    final chapter = await File(
      '${imported.filePath}/OEBPS/chapter1.xhtml',
    ).readAsString();
    expect(chapter, contains('<ruby>憂鬱<rt>ゆううつ</rt></ruby>'));
  });

  // UI-level coverage of runFuriganaExport: long-press → options sheet →
  // coverage dialog → spinner → save. The SAF save dialog is the one thing
  // that cannot run headless, so the platform side of FilePicker is swapped
  // for a capturing fake; everything up to it is the real code path.
  //
  // Never pumpAndSettle while book tiles are mounted — _CoverTilt's sensor
  // stream rebuilds at 60fps on device and the frame never settles.
  group('export UI', () {
    late _CapturingFilePicker picker;
    late FilePickerPlatform originalPicker;

    setUp(() {
      originalPicker = FilePickerPlatform.instance;
      picker = _CapturingFilePicker();
      FilePickerPlatform.instance = picker;
    });

    tearDown(() {
      FilePickerPlatform.instance = originalPicker;
    });

    Future<AppDatabase> dbWithBook(String body, {required String title}) async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final path = await writeEpub(body);
      await db
          .into(db.books)
          .insert(BooksCompanion.insert(title: title, filePath: path));
      return db;
    }

    testWidgets(
      'long-press → Export as EPUB → All kanji saves a ruby-annotated EPUB',
      (tester) async {
        final db = await dbWithBook('<p>吾輩は猫である。</p>', title: '吾輩は猫である');
        await tester.pumpWidget(
          buildIntegrationTestApp(db: db, home: const LibraryScreen()),
        );
        final bookId = (await db.select(db.books).get()).single.id;
        final tile = find.byKey(ValueKey('book-tile-$bookId'));
        await pumpUntilVisible(tester, tile);

        await longPressTile(tester, tile);
        expect(find.text('Export as EPUB'), findsOneWidget);
        await tapSheetItem(tester, 'Export as EPUB');

        // Coverage dialog: all four modes; the level picker only appears
        // for the JLPT mode.
        expect(find.text('Furigana in exported book'), findsOneWidget);
        expect(find.byType(RadioListTile<FuriganaMode>), findsNWidgets(4));
        expect(find.text('All kanji'), findsOneWidget);
        expect(find.text('Kanji above JLPT level'), findsOneWidget);
        expect(find.text('As published'), findsOneWidget);
        expect(find.text('None (remove existing)'), findsOneWidget);
        expect(find.byType(SegmentedButton<int>), findsNothing);

        // Cancel is a no-op: no spinner, nothing saved.
        await tester.tap(find.text('Cancel'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Furigana in exported book'), findsNothing);
        expect(find.text('Preparing EPUB…'), findsNothing);
        expect(picker.calls, 0);

        // Export with the default mode (all kanji).
        await longPressTile(tester, tile);
        await tapSheetItem(tester, 'Export as EPUB');
        await tester.tap(find.text('Export'));
        await pumpUntilVisible(
          tester,
          find.text('EPUB exported'),
          timeout: const Duration(seconds: 90),
        );
        // The snackbar shows while the spinner's pop animation may still be
        // running; wait for the route to actually leave the tree.
        await pumpUntilGone(tester, find.text('Preparing EPUB…'));

        expect(picker.calls, 1);
        expect(picker.fileName, '吾輩は猫である (furigana).epub');
        expect(picker.dialogTitle, 'Save EPUB');
        final xhtml = chapterOut(picker.bytes!);
        expect(xhtml, contains('<ruby>猫<rt>ねこ</rt></ruby>'));
      },
    );

    testWidgets('JLPT level picker and None mode reach the pipeline', (
      tester,
    ) async {
      // 今日 = N5, 憂鬱 = N1, 薔薇 = non-joyo (harder than N1), plus
      // publisher ruby. At threshold N1 only 薔薇 gains ruby — which a
      // level-agnostic fixture could never prove reached the pipeline.
      final db = await dbWithBook(
        '<p>今日は憂鬱な薔薇だ。</p><p><ruby>漢字<rt>かんじ</rt></ruby></p>',
        title: 'JLPTの本',
      );
      await tester.pumpWidget(
        buildIntegrationTestApp(db: db, home: const LibraryScreen()),
      );
      final bookId = (await db.select(db.books).get()).single.id;
      final tile = find.byKey(ValueKey('book-tile-$bookId'));
      await pumpUntilVisible(tester, tile);

      await longPressTile(tester, tile);
      await tapSheetItem(tester, 'Export as EPUB');
      await tester.tap(find.text('Kanji above JLPT level'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(SegmentedButton<int>), findsOneWidget);
      for (final label in ['N5', 'N4', 'N3', 'N2', 'N1']) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.text('N1'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Export'));
      await pumpUntilVisible(
        tester,
        find.text('EPUB exported'),
        timeout: const Duration(seconds: 90),
      );

      expect(picker.calls, 1);
      var xhtml = chapterOut(picker.bytes!);
      // Reading-agnostic on 薔薇 so a MeCab dictionary swap can't break it.
      expect(
        RegExp(r'<ruby>薔薇<rt>[ぁ-ん]+</rt></ruby>').hasMatch(xhtml),
        isTrue,
        reason: 'non-joyo word should be annotated at every threshold',
      );
      expect(xhtml, isNot(contains('<ruby>憂鬱')));
      expect(xhtml, isNot(contains('<ruby>今日')));
      expect(xhtml, contains('<rt>かんじ</rt>')); // publisher ruby kept

      // Let the snackbar clear so the next export waits on a fresh one.
      await pumpUntilGone(tester, find.text('EPUB exported'));

      // None (remove existing) strips ALL ruby, publisher's included.
      await longPressTile(tester, tile);
      await tapSheetItem(tester, 'Export as EPUB');
      await tester.tap(find.text('None (remove existing)'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Export'));
      await pumpUntilVisible(
        tester,
        find.text('EPUB exported'),
        timeout: const Duration(seconds: 60),
      );

      expect(picker.calls, 2);
      xhtml = chapterOut(picker.bytes!);
      expect(xhtml, isNot(contains('<ruby')));
      expect(xhtml, isNot(contains('<rt>')));
      expect(xhtml, contains('憂鬱'));
      expect(xhtml, contains('漢字'));
    });
  });
}

/// Captures what runFuriganaExport hands to the platform save dialog.
/// Extending FilePickerPlatform inherits the real verification token, so the
/// instance setter accepts it without any mock machinery.
class _CapturingFilePicker extends FilePickerPlatform {
  int calls = 0;
  Uint8List? bytes;
  String? fileName;
  String? dialogTitle;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    required String fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    required Uint8List bytes,
    Function(FilePickerStatus)? onFileLoading,
    bool lockParentWindow = false,
  }) async {
    calls++;
    this.bytes = bytes;
    this.fileName = fileName;
    this.dialogTitle = dialogTitle;
    return '/fake/exported.epub';
  }
}
