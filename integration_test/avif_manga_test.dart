import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/data/services/manga_cache_store.dart';
import 'package:mekuru/features/manga/data/services/mokuro_parser.dart';
import 'package:mekuru/features/manga/presentation/screens/manga_reader_screen.dart';
import 'package:path/path.dart' as p;

import '../test/shared/avif_header.dart';
import 'shared/test_infrastructure.dart';
import 'test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('avif_manga_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
    await cleanupAppBooksDir();
  });

  // Flutter decodes AVIF itself only on Android 12+; iOS reads it with
  // ImageIO and Android 7-11 with libavif, so run this on each.
  testWidgets('imports an AVIF CBZ and shows its pages', (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final page = base64Decode(avifPageBase64);
    final archive = Archive();
    for (final name in ['0001.avif', '0002.avif']) {
      archive.addFile(ArchiveFile(name, page.length, page));
    }
    final cbz = p.join(tempDir.path, 'avif.cbz');
    await File(cbz).writeAsBytes(ZipEncoder().encode(archive));

    final book = await BookRepository(db).importCbz(cbz);
    final manga = await MangaCacheStore.read(
      p.join(book.filePath, mangaPagesCacheFileName),
    );
    expect(
      [
        for (final page in manga.pages) [page.imgWidth, page.imgHeight],
      ],
      [
        [96, 128],
        [96, 128],
      ],
    );

    // Auto-crop decodes the page to pixels as well.
    final bounds = await MokuroParser.computeImageContentBounds(
      p.join(manga.imageDirPath, manga.pages.first.imageFileName),
    );
    expect(bounds, isNotNull);

    await tester.pumpWidget(
      buildIntegrationTestApp(
        db: db,
        home: MangaReaderScreen(book: book),
      ),
    );
    await pumpUntilVisible(
      tester,
      find.byWidgetPredicate(
        (widget) =>
            widget is RawImage &&
            widget.image?.width == 96 &&
            widget.image?.height == 128,
      ),
    );
    expect(find.byIcon(Icons.broken_image), findsNothing);
  });
}
