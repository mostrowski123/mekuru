import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart' show getCrc32;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/manga/presentation/screens/manga_reader_screen.dart';
import 'package:path/path.dart' as p;

import '../test/shared/rar_fixtures.dart';
import 'shared/test_infrastructure.dart';
import 'test_helpers.dart';

/// CBR import on device: the RAR reader's native library (libarchive, built
/// by packages/rar_reader's hook) loads and decompresses, and a CBR becomes a
/// manga book that opens in the reader.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('comic_archive_');
    await cleanupAppBooksDir();
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
    await cleanupAppBooksDir();
  });

  Future<String> write(String name, List<int> bytes) async {
    final path = p.join(tempDir.path, name);
    await File(path).writeAsBytes(bytes);
    return path;
  }

  testWidgets('libarchive decompresses RAR 4 and solid RAR 5', (tester) async {
    final rar4 = readRar(await write('normal.rar', rar4CompressNormal));
    expect(rar4['LibarchiveAddingTest.html'], hasLength(20111));
    expect(utf8.decode(rar4['testdir/test.txt']!), 'test text document\r\n');

    final rar5 = readRar(await write('solid.rar', rar5Solid));
    expect(rar5, hasLength(7));
    expect(getCrc32(rar5['test6.bin']!), 0x36A448FF);
  });

  testWidgets('a CBR imports as a manga book and opens in the reader', (
    tester,
  ) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final page = img.encodePng(img.Image(width: 300, height: 500));
    final cbr = await write(
      'Vol 1.cbr',
      storedRar5({
        'Vol 1/002.png': page,
        'Vol 1/001.png': page,
        'ComicInfo.xml': utf8.encode('<ComicInfo/>'),
      }),
    );

    final imported = await BookRepository(db).importCbz(cbr);

    expect(imported.book.title, 'Vol 1');
    expect(imported.book.bookType, 'manga');
    expect(imported.book.totalPages, 2);
    expect(imported.hasOcr, isFalse);

    await tester.pumpWidget(
      buildIntegrationTestApp(
        db: db,
        home: MangaReaderScreen(book: imported.book),
      ),
    );
    await pumpUntilVisible(tester, find.byType(PageView));
  });
}
