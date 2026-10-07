// A bookmark opened from the library: the reader starts at the bookmark,
// not at the saved position, and closing the reader goes back to the
// library (the bookmarks sheet used to pop the library's route as well,
// leaving nothing under the reader). One reader per file: see
// integration_test/shared/scroll_view_fixture.dart.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/library/presentation/screens/library_screen.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/data/repositories/bookmark_repository.dart';
import 'package:mekuru/features/reader/presentation/widgets/custom_epub_viewer.dart';

import 'shared/scroll_view_fixture.dart' show writeScrollViewEpub;
import 'shared/test_infrastructure.dart';
import 'test_helpers.dart';

const _title = 'しおりテスト';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('library_bookmark_');
    await cleanupAppBooksDir();
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
    await cleanupAppBooksDir();
  });

  testWidgets('a bookmark opened from the library starts the reader there', (
    tester,
  ) async {
    final l10n = await loadExpectedL10n();
    final db = createTestDatabase();
    addTearDown(db.close);
    final book = await BookRepository(db).importEpub(
      await writeScrollViewEpub(tempDir, title: _title, vertical: false),
    );
    // Saved position: chapter 1 (written without lastReadAt, so the book
    // has no second tile among the recently read). Bookmark: chapter 2.
    await (db.update(db.books)..where((t) => t.id.equals(book.id))).write(
      const BooksCompanion(lastReadCfi: Value('epubcfi(/6/2!/4/2/1:0)')),
    );
    await BookmarkRepository(db).addBookmark(
      bookId: book.id,
      cfi: 'epubcfi(/6/4!/4/2/1:0)',
      progress: 0.5,
      chapterTitle: 'c2',
    );

    final storage = InMemoryReaderSettingsStorage();
    await storage.save(const ReaderSettings(scrollView: true));
    await tester.pumpWidget(
      buildIntegrationTestApp(
        db: db,
        home: const LibraryScreen(),
        readerSettingsStorage: storage,
      ),
    );
    await pumpUntilVisible(tester, find.text(_title));

    await tester.longPress(find.text(_title).first);
    await pumpUntilVisible(tester, find.text(l10n.libraryBookmarksTitle));
    await tester.tap(find.text(l10n.libraryBookmarksTitle));
    await pumpUntilVisible(tester, find.text('c2'));
    await tester.tap(find.text('c2'));

    await pumpUntilVisible(tester, find.byType(CustomEpubViewer));
    await pumpUntilGone(
      tester,
      find.byKey(const Key('reader-loading-overlay')),
      timeout: const Duration(seconds: 20),
    );
    final controller = tester
        .widget<CustomEpubViewer>(find.byType(CustomEpubViewer))
        .controller;
    var shown = -1;
    for (var tick = 0; tick < 50 && shown != 1; tick++) {
      await tester.pump(const Duration(milliseconds: 200));
      shown =
          (await evalJson(
                controller,
                'JSON.stringify({index: rendition.currentLocation().start'
                ' ? rendition.currentLocation().start.index : -1})',
              ))['index']
              as int;
    }
    expect(shown, 1, reason: 'the reader opened away from the bookmark');

    // Leaving the reader shows the library again.
    Navigator.of(tester.element(find.byType(CustomEpubViewer))).pop();
    await pumpUntilGone(tester, find.byType(CustomEpubViewer));
    await pumpUntilVisible(tester, find.text(_title));
    expect(find.byType(LibraryScreen), findsOneWidget);
  });
}
