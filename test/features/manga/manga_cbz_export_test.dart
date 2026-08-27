import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/data/services/manga_cbz_export.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../../shared/epub_fixtures.dart';
import '../../shared/fake_path_provider.dart';
import '../../shared/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('cbz_export_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {
        // Windows can hold locks on freshly written files.
      }
    }
  });

  List<int> png(int width, int height) =>
      img.encodePng(img.Image(width: width, height: height));

  /// Builds a manga cache dir whose pages are in [images] insertion order.
  /// A page maps to null when it should be listed in the cache but have no
  /// file on disk.
  Future<String> buildCacheDir(
    Map<String, List<int>?> images, {
    String? safTreeUri,
  }) async {
    final cacheDir = Directory(p.join(tempDir.path, 'cache'))
      ..createSync(recursive: true);
    final imagesDir = Directory(p.join(cacheDir.path, 'images'))
      ..createSync(recursive: true);
    var index = 0;
    final pages = <MokuroPage>[];
    for (final entry in images.entries) {
      if (entry.value != null) {
        File(p.join(imagesDir.path, entry.key)).writeAsBytesSync(entry.value!);
      }
      pages.add(
        MokuroPage(
          pageIndex: index++,
          imageFileName: entry.key,
          imgWidth: 0,
          imgHeight: 0,
          blocks: const [],
        ),
      );
    }
    final book = MokuroBook(
      title: 'export test',
      imageDirPath: imagesDir.path,
      safTreeUri: safTreeUri,
      safImageDirRelativePath: safTreeUri != null ? 'images' : null,
      ocrCompleted: false,
      pages: pages,
    );
    File(
      p.join(cacheDir.path, 'pages_cache.json'),
    ).writeAsStringSync(jsonEncode(book.toJson()));
    return cacheDir.path;
  }

  group('writeCbz', () {
    test(
      'writes pages in cache order under zero-padded stored names',
      () async {
        // Cache order (z before a) deliberately disagrees with name order.
        final zBytes = png(10, 100);
        final aBytes = png(11, 101);
        final cacheDir = await buildCacheDir({
          'z.png': zBytes,
          'a.png': aBytes,
        });
        final outPath = p.join(tempDir.path, 'out.cbz');

        final written = await writeCbz(cacheDir, outPath);

        expect(written, 2);
        final archive = ZipDecoder().decodeBytes(
          await File(outPath).readAsBytes(),
        );
        expect(archive.files.map((f) => f.name), ['0001.png', '0002.png']);
        expect(
          archive.files.first.content,
          zBytes,
          reason: 'entry 0001 must be the first page in cache order',
        );
        expect(archive.files.first.content, isNot(equals(aBytes)));
        expect(
          archive.files.map((f) => f.compression),
          everyElement(CompressionType.none),
          reason: 'pages must be stored, not deflated',
        );
      },
    );

    test('skips pages whose image is missing and exports the rest', () async {
      final cacheDir = await buildCacheDir({
        'p1.png': png(8, 8),
        'gone.png': null,
        'p3.png': png(8, 8),
      });
      final outPath = p.join(tempDir.path, 'out.cbz');

      final written = await writeCbz(cacheDir, outPath);

      expect(written, 2);
      final archive = ZipDecoder().decodeBytes(
        await File(outPath).readAsBytes(),
      );
      expect(archive.files, hasLength(2));
    });

    test('throws when the book has no exportable pages', () async {
      final cacheDir = await buildCacheDir({'gone.png': null});
      final outPath = p.join(tempDir.path, 'out.cbz');

      await expectLater(
        writeCbz(cacheDir, outPath),
        throwsA(isA<EmptyMangaExportException>()),
      );
      expect(File(outPath).existsSync(), isFalse);
    });

    test('refuses SAF-backed books', () async {
      final cacheDir = await buildCacheDir({
        'p1.png': png(8, 8),
      }, safTreeUri: 'content://com.android.externalstorage.documents/tree/x');

      await expectLater(
        writeCbz(cacheDir, p.join(tempDir.path, 'out.cbz')),
        throwsA(isA<SafMangaExportUnsupportedException>()),
      );
    });
  });

  group('convert → export → re-import round trip', () {
    test(
      'a converted EPUB exports to a CBZ that imports identically',
      () async {
        PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);
        final db = createTestDatabase();
        addTearDown(db.close);
        final repo = BookRepository(db);

        final epubPath = await createFixedLayoutMangaEpub(pageCount: 3);
        addTearDown(() {
          final dir = Directory(p.dirname(epubPath));
          if (dir.existsSync()) dir.deleteSync(recursive: true);
        });
        final converted = await repo.convertEpubToManga(
          await repo.importEpub(epubPath),
        );

        final outPath = p.join(tempDir.path, 'roundtrip.cbz');
        await writeCbz(converted.filePath, outPath);
        final reimported = await repo.importCbz(outPath);

        expect(reimported.totalPages, converted.totalPages);
        final cacheFile = File(p.join(reimported.filePath, 'pages_cache.json'));
        final cache = MokuroBook.fromJson(
          jsonDecode(await cacheFile.readAsString()) as Map<String, dynamic>,
        );
        expect(
          [cache.pages.first.imgWidth, cache.pages.first.imgHeight],
          [10, 100],
          reason: 'first page must survive the round trip with its dimensions',
        );
      },
    );
  });
}
