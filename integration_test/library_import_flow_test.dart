import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/library/presentation/screens/library_screen.dart';
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
  // BookRepository.importEpub copies the EPUB into the app's support
  // directory under books/. Tests should clean it up so consecutive runs
  // start from a fresh library.
  final appDir = await getApplicationSupportDirectory();
  final booksDir = Directory(p.join(appDir.path, 'books'));
  if (await booksDir.exists()) {
    await booksDir.delete(recursive: true);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('library_import_');
    await _cleanupAppBooksDir();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
    await _cleanupAppBooksDir();
  });

  testWidgets(
    'importEpub parses metadata, persists the book, and renders it in the library grid',
    (tester) async {
      final db = createTestDatabase();
      addTearDown(db.close);

      final fixturePath = await _writeFixtureEpub(tempDir, title: '走れメロス');

      final imported = await BookRepository(db).importEpub(fixturePath);
      expect(imported.title, '走れメロス');
      expect(imported.language, 'ja');

      await tester.pumpWidget(
        buildIntegrationTestApp(db: db, home: const LibraryScreen()),
      );
      await pumpUntilVisible(tester, find.text('走れメロス'));

      // The tile renders the title in two text styles (label + body) for
      // layout reasons, so >=1 is the right assertion here.
      expect(find.text('走れメロス'), findsAtLeastNWidgets(1));
      expect(find.byType(LibraryScreen), findsOneWidget);
    },
  );

  testWidgets(
    'importing two EPUBs renders both tiles in the grid',
    (tester) async {
      final db = createTestDatabase();
      addTearDown(db.close);

      final repo = BookRepository(db);
      final firstPath = await _writeFixtureEpub(
        Directory(p.join(tempDir.path, 'a'))..createSync(),
        title: 'こころ',
      );
      final secondPath = await _writeFixtureEpub(
        Directory(p.join(tempDir.path, 'b'))..createSync(),
        title: '坊っちゃん',
      );

      await repo.importEpub(firstPath);
      await repo.importEpub(secondPath);

      await tester.pumpWidget(
        buildIntegrationTestApp(db: db, home: const LibraryScreen()),
      );
      await pumpUntilVisible(tester, find.text('こころ'));

      expect(find.text('こころ'), findsAtLeastNWidgets(1));
      expect(find.text('坊っちゃん'), findsAtLeastNWidgets(1));
    },
  );
}
