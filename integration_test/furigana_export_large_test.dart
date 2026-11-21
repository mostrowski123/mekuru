import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/library/presentation/screens/library_screen.dart';
import 'package:mekuru/features/reader/data/services/mecab_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'shared/test_infrastructure.dart';
import 'test_helpers.dart';

/// Local only: "Export as EPUB" of a book hundreds of MB big, through the
/// real UI and the real system save dialog, while a host samples the app's
/// memory. Not in CI: the book is too big to generate there, and a host has
/// to answer the save dialog. The host, in order:
///
///  1. Pushes an EPUB titled [_title] whose chapters hold kanji to
///     `files/large.epub`, then creates `files/large.epub.done`.
///  2. Backs out of the first save dialog. Nothing is saved, and the
///     export's temp file must be gone.
///  3. Taps Save in the second. "EPUB exported" must show and the temp file
///     be gone. The host then pushes the saved copy back to
///     `files/saved.epub` (+ `.done`), and the test imports it.
///
/// Each step prints a `LARGE MARK` line for the host to follow.
const _title = '大きな本';

void _mark(String step) =>
    // ignore: avoid_print
    print('LARGE MARK ${DateTime.now().toIso8601String()} $step');

/// Waits up to [timeout] for the host to push [path] (it creates
/// `<path>.done` when the copy is complete), deleting both at teardown.
Future<String> _pushed(String path, Duration timeout) async {
  final done = File('$path.done');
  addTearDown(() async {
    for (final f in [File(path), done]) {
      if (f.existsSync()) await f.delete();
    }
  });
  _mark('waiting for ${p.basename(path)}');
  final end = DateTime.now().add(timeout);
  while (!done.existsSync() && DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  expect(done.existsSync(), isTrue, reason: 'nothing pushed to $path');
  return path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => MecabService.instance.init());

  testWidgets('a large EPUB exports, saves and reopens', (tester) async {
    final files = (await getApplicationSupportDirectory()).path;
    final book = await _pushed(
      p.join(files, 'large.epub'),
      const Duration(minutes: 10),
    );
    final temp = p.join(
      (await getTemporaryDirectory()).path,
      '$_title (furigana).epub',
    );

    final db = createTestDatabase();
    addTearDown(db.close);
    await db
        .into(db.books)
        .insert(BooksCompanion.insert(title: _title, filePath: book));
    await tester.pumpWidget(
      buildIntegrationTestApp(db: db, home: const LibraryScreen()),
    );
    final bookId = (await db.select(db.books).get()).single.id;
    final tile = find.byKey(ValueKey('book-tile-$bookId'));
    await pumpUntilVisible(tester, tile);

    Future<void> export(String answer) async {
      await longPressTile(tester, tile);
      await tapSheetItem(tester, 'Export as EPUB');
      await tester.tap(find.text('Export'));
      _mark('export tapped');
      await pumpUntilVisible(tester, find.text('Preparing EPUB…'));
      await pumpUntilGone(
        tester,
        find.text('Preparing EPUB…'),
        timeout: const Duration(minutes: 10),
      );
      // The host waits before answering, so the export is still here.
      expect(File(temp).existsSync(), isTrue, reason: 'no export at $temp');
      _mark('save dialog asked: $answer');
    }

    Future<void> tempGone() async {
      for (var i = 0; i < 480 && File(temp).existsSync(); i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(File(temp).existsSync(), isFalse, reason: 'temp file left');
    }

    await export('back');
    await tempGone();
    expect(find.text('EPUB exported'), findsNothing);
    _mark('cancelled');

    await export('save');
    await pumpUntilVisible(
      tester,
      find.text('EPUB exported'),
      timeout: const Duration(minutes: 5),
    );
    await tempGone();
    _mark('saved');

    final saved = await _pushed(
      p.join(files, 'saved.epub'),
      const Duration(minutes: 10),
    );
    addTearDown(cleanupAppBooksDir);
    final imported = await BookRepository(db).importEpub(saved);
    expect(imported.title, _title);
    final annotated = await Directory(imported.filePath)
        .list(recursive: true)
        .where((e) => e is File && e.path.endsWith('.xhtml'))
        .asyncMap((e) => (e as File).readAsString())
        .any((xhtml) => xhtml.contains('<rt>'));
    expect(annotated, isTrue, reason: 'no chapter of the saved copy has ruby');
    _mark('reimported');
  });
}
