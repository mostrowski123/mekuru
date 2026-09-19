import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:path/path.dart' as p;

/// iOS copies a folder-imported manga's pages into the app (a picked folder
/// is readable for one session only); the manifest comes from a user file, so
/// its image names are untrusted.
void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('copy_pages_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('copies pages into <cacheDir>/pages and skips escaping names', () async {
    final source = Directory(p.join(root.path, 'picked', 'vol1'))
      ..createSync(recursive: true);
    File(p.join(source.path, '001.jpg')).writeAsStringSync('a');
    Directory(p.join(source.path, 'extra')).createSync();
    File(p.join(source.path, 'extra', '002.jpg')).writeAsStringSync('b');
    File(p.join(root.path, 'picked', 'secret.txt')).writeAsStringSync('s');
    final cacheDir = Directory(p.join(root.path, 'books', 'manga_1'))
      ..createSync(recursive: true);

    final pagesPath = await BookRepository.copyPagesInto(
      cacheDir,
      MokuroBookManifest(
        title: 't',
        htmlPath: '',
        imageDirPath: source.path,
        ocrDirPath: '',
        imageFileNames: const ['001.jpg', 'extra/002.jpg', '../secret.txt'],
      ),
    );

    expect(pagesPath, p.join(cacheDir.path, 'pages'));
    expect(File(p.join(pagesPath, '001.jpg')).readAsStringSync(), 'a');
    expect(File(p.join(pagesPath, 'extra', '002.jpg')).readAsStringSync(), 'b');
    expect(File(p.join(cacheDir.path, 'secret.txt')).existsSync(), isFalse);
  });
}
