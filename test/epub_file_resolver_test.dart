import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/reader/data/services/epub_file_resolver.dart';
import 'package:path/path.dart' as p;

void main() {
  group('EpubFileResolver', () {
    late Directory tempDir;
    late EpubFileResolver resolver;

    setUp(() {
      resolver = EpubFileResolver();
      tempDir = Directory.systemTemp.createTempSync('epub_resolver_test_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('returns path when stored path is an EPUB file', () async {
      final epubFile = File(p.join(tempDir.path, 'book.epub'));
      await epubFile.writeAsString('stub');

      final resolved = await resolver.resolveLocalEpubPath(epubFile.path);

      expect(resolved, epubFile.path);
    });

    test('resolves EPUB from parent directory when stored path is content dir', () async {
      final bookDir = Directory(p.join(tempDir.path, 'book_123'));
      final contentDir = Directory(p.join(bookDir.path, 'content'));
      await contentDir.create(recursive: true);

      final epubFile = File(p.join(bookDir.path, 'my-book.epub'));
      await epubFile.writeAsString('stub');

      final resolved = await resolver.resolveLocalEpubPath(contentDir.path);

      expect(resolved, epubFile.path);
    });

    test('throws when no EPUB can be resolved', () async {
      final contentDir = Directory(p.join(tempDir.path, 'content'));
      await contentDir.create(recursive: true);

      expect(
        () => resolver.resolveLocalEpubPath(contentDir.path),
        throwsA(isA<FileSystemException>()),
      );
    });
  });
}
