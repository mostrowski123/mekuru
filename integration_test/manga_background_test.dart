// The manga background follows the page on screen: Auto takes its edge
// colour and Blur draws the page behind itself, both from the image the
// page view has already decoded. No WebView.

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/manga/presentation/screens/manga_reader_screen.dart';
import 'package:mekuru/features/manga/presentation/widgets/manga_backdrop.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:path/path.dart' as p;

import 'shared/test_infrastructure.dart';
import 'test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('manga_background_');
    await cleanupAppBooksDir();
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
    await cleanupAppBooksDir();
  });

  testWidgets('auto and blur take their colours from the page on screen', (
    tester,
  ) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final page = img.encodePng(
      img.fill(
        img.Image(width: 200, height: 300),
        color: img.ColorRgb8(200, 30, 30),
      ),
    );
    final archive = Archive();
    for (final name in ['1.png', '2.png']) {
      archive.addFile(ArchiveFile(name, page.length, page));
    }
    final cbz = p.join(tempDir.path, 'red.cbz');
    await File(cbz).writeAsBytes(ZipEncoder().encode(archive));
    final book = (await BookRepository(db).importCbz(cbz)).book;

    final settings = InMemoryReaderSettingsStorage();
    await settings.save(
      const ReaderSettings(mangaBackground: MangaBackground.auto),
    );
    await tester.pumpWidget(
      buildIntegrationTestApp(
        db: db,
        home: MangaReaderScreen(book: book),
        readerSettingsStorage: settings,
      ),
    );

    // A GPU may round a channel by one.
    bool isPageRed(Color c) =>
        ((c.r * 255) - 200).abs() < 4 &&
        ((c.g * 255) - 30).abs() < 4 &&
        ((c.b * 255) - 30).abs() < 4;
    final backdrop = find.byType(MangaBackdrop);
    await pumpUntilVisible(
      tester,
      find.descendant(
        of: backdrop,
        matching: find.byWidgetPredicate(
          (w) => w is ColoredBox && isPageRed(w.color),
        ),
      ),
    );

    ProviderScope.containerOf(tester.element(backdrop))
        .read(readerSettingsProvider.notifier)
        .setMangaBackground(MangaBackground.blur);
    await pumpUntilVisible(
      tester,
      find.descendant(
        of: backdrop,
        matching: find.byWidgetPredicate(
          (w) => w is RawImage && w.image != null,
        ),
      ),
    );
  });
}
