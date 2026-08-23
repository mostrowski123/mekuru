import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../../shared/epub_fixtures.dart';
import '../../shared/test_database.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.root);
  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late BookRepository repo;
  late Directory tempDir;

  setUp(() {
    db = createTestDatabase();
    repo = BookRepository(db);
    tempDir = Directory.systemTemp.createTempSync('cbz_import_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
  });

  tearDown(() async {
    await db.close();
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

  Future<String> createCbz(String name, Map<String, List<int>> entries) async {
    final archive = Archive();
    for (final entry in entries.entries) {
      archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
    }
    final path = p.join(tempDir.path, '$name.cbz');
    await File(path).writeAsBytes(ZipEncoder().encode(archive));
    return path;
  }

  Future<MokuroBook> readPagesCache(String bookFilePath) async {
    final cacheFile = File(p.join(bookFilePath, 'pages_cache.json'));
    return MokuroBook.fromJson(
      jsonDecode(await cacheFile.readAsString()) as Map<String, dynamic>,
    );
  }

  group('BookRepository.importCbz', () {
    test('each page keeps its own dimensions after the natural sort', () async {
      // The archive order, the natural-sorted order, and the sizes are all
      // deliberately different. Dimensions are collected during extraction but
      // imageFileNames is natural-sorted afterwards, so a page must be matched
      // by name — an index-aligned lookup would silently mismatch here.
      final cbzPath = await createCbz('sorted', {
        'page_10.png': png(30, 40),
        'page_2.png': png(10, 20),
        'page_1.png': png(50, 60),
      });

      final book = await repo.importCbz(cbzPath);
      final cache = await readPagesCache(book.filePath);

      expect(
        cache.pages.map((page) => page.imageFileName),
        ['page_1.png', 'page_2.png', 'page_10.png'],
        reason: 'pages must be in natural order',
      );
      expect(
        cache.pages.map((page) => '${page.imgWidth}x${page.imgHeight}'),
        ['50x60', '10x20', '30x40'],
        reason: 'each page must carry the size of its own image',
      );
      expect(cache.pages.map((page) => page.pageIndex), [0, 1, 2]);
    });

    test('records the book with a page count and manga type', () async {
      final cbzPath = await createCbz('counted', {
        'a.png': png(8, 8),
        'b.png': png(8, 8),
      });

      final book = await repo.importCbz(cbzPath);

      expect(book.title, 'counted');
      expect(book.bookType, 'manga');
      expect(book.totalPages, 2);
      expect(book.coverImagePath, contains('a.png'));
      expect(await repo.getAllBooks(), hasLength(1));
    });

    test('falls back to zero for a page whose header is unreadable', () async {
      final cbzPath = await createCbz('partly_bad', {
        'good.png': png(12, 34),
        // Passes the extension filter but carries no usable header.
        'bad.jpg': [0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0],
      });

      final book = await repo.importCbz(cbzPath);
      final cache = await readPagesCache(book.filePath);

      final bad = cache.pages.firstWhere((pg) => pg.imageFileName == 'bad.jpg');
      final good = cache.pages.firstWhere(
        (pg) => pg.imageFileName == 'good.png',
      );
      expect([bad.imgWidth, bad.imgHeight], [0, 0]);
      expect([good.imgWidth, good.imgHeight], [12, 34]);
      expect(
        cache.pages,
        hasLength(2),
        reason: 'an unreadable page must not be dropped from the book',
      );
    });

    test('imports JPEG pages, not only PNG', () async {
      final cbzPath = await createCbz('jpeg_pages', {
        'p1.jpg': img.encodeJpg(img.Image(width: 64, height: 96)),
      });

      final cache = await readPagesCache(
        (await repo.importCbz(cbzPath)).filePath,
      );

      expect(
        [cache.pages.single.imgWidth, cache.pages.single.imgHeight],
        [64, 96],
      );
    });

    test('reports progress monotonically from 0 to 1', () async {
      final cbzPath = await createCbz('progress', {
        'a.png': png(8, 8),
        'b.png': png(8, 8),
        'c.png': png(8, 8),
        'd.png': png(8, 8),
      });
      final seen = <double>[];

      await repo.importCbz(cbzPath, onProgress: seen.add);

      expect(seen, isNotEmpty);
      expect(seen.last, 1.0);
      expect(seen.first, greaterThan(0.0));
      for (var i = 1; i < seen.length; i++) {
        expect(
          seen[i],
          greaterThanOrEqualTo(seen[i - 1]),
          reason: 'progress must never go backwards',
        );
      }
    });

    test('leaves OCR unmarked so it can be run later', () async {
      final cbzPath = await createCbz('no_ocr', {'a.png': png(8, 8)});

      final cache = await readPagesCache(
        (await repo.importCbz(cbzPath)).filePath,
      );

      expect(cache.ocrCompleted, isFalse);
      expect(cache.pages.single.blocks, isEmpty);
    });
  });

  group('BookRepository import failure cleanup', () {
    List<Directory> leftoverBookDirs() {
      final booksDir = Directory(p.join(tempDir.path, 'books'));
      if (!booksDir.existsSync()) return const [];
      return booksDir.listSync().whereType<Directory>().toList();
    }

    Future<void> expectNothingStranded() async {
      expect(
        leftoverBookDirs(),
        isEmpty,
        reason: 'a failed import must not strand its directory in app storage',
      );
      expect(await repo.getAllBooks(), isEmpty);
    }

    test('importEpub deletes the book directory when import fails', () async {
      final corruptPath = p.join(tempDir.path, 'corrupt.epub');
      await File(corruptPath).writeAsBytes(corruptZipBytes);

      await expectLater(
        repo.importEpub(corruptPath),
        throwsA(isA<FileSystemException>()),
      );

      await expectNothingStranded();
    });

    test('importCbz deletes the cache directory when import fails', () async {
      // The cache directory is created before the source is opened, so a
      // missing source file exercises the cleanup path.
      await expectLater(
        repo.importCbz(p.join(tempDir.path, 'missing.cbz')),
        throwsA(anything),
      );

      await expectNothingStranded();
    });
  });
}
