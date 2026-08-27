import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/library/data/services/epub_manga_converter.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../../shared/epub_fixtures.dart';
import '../../shared/fake_path_provider.dart';
import '../../shared/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late BookRepository repo;
  late Directory tempDir;

  setUp(() {
    db = createTestDatabase();
    repo = BookRepository(db);
    tempDir = Directory.systemTemp.createTempSync('epub_manga_convert_');
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);
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

  Future<Book> importFixture(String epubPath) async {
    final book = await repo.importEpub(epubPath);
    addTearDown(() {
      final fixtureDir = Directory(p.dirname(epubPath));
      if (fixtureDir.existsSync()) fixtureDir.deleteSync(recursive: true);
    });
    return book;
  }

  Future<MokuroBook> readPagesCache(String bookFilePath) async {
    final cacheFile = File(p.join(bookFilePath, 'pages_cache.json'));
    return MokuroBook.fromJson(
      jsonDecode(await cacheFile.readAsString()) as Map<String, dynamic>,
    );
  }

  group('BookRepository.convertEpubToManga', () {
    test('converts an image-only EPUB into a manga book in place', () async {
      final book = await importFixture(
        await createFixedLayoutMangaEpub(pageCount: 4),
      );
      await repo.updateProgress(book.id, 'epubcfi(/6/4!/4/2)', progress: 0.5);
      final bookDir = p.dirname(book.filePath);

      final converted = await repo.convertEpubToManga(
        (await repo.getBookById(book.id))!,
      );

      expect(converted.id, book.id, reason: 'same row, flipped in place');
      expect(converted.bookType, 'manga');
      expect(converted.filePath, bookDir);
      expect(converted.totalPages, 4);
      expect(converted.readProgress, 0.0);
      expect(converted.lastReadCfi, isNull);
      expect(converted.coverImagePath, p.join(bookDir, 'images', '0001.png'));

      final cache = await readPagesCache(converted.filePath);
      expect(cache.ocrCompleted, isFalse);
      expect(cache.imageDirPath, p.join(bookDir, 'images'));
      expect(cache.pages.map((pg) => pg.imageFileName), [
        '0001.png',
        '0002.png',
        '0003.png',
        '0004.png',
      ]);
      expect(cache.pages.map((pg) => pg.pageIndex), [0, 1, 2, 3]);
      expect(cache.pages.every((pg) => pg.blocks.isEmpty), isTrue);
      expect(
        cache.pages.map((pg) => '${pg.imgWidth}x${pg.imgHeight}'),
        ['10x100', '11x101', '12x102', '13x103'],
        reason: 'each page carries its own header-read dimensions',
      );

      final imageFiles = Directory(
        p.join(bookDir, 'images'),
      ).listSync().whereType<File>();
      expect(imageFiles, hasLength(4));
      expect(
        Directory(p.join(bookDir, 'content')).existsSync(),
        isFalse,
        reason: 'extracted EPUB content is removed after conversion',
      );
      expect(
        Directory(bookDir).listSync().whereType<File>().where(
          (f) => f.path.toLowerCase().endsWith('.epub'),
        ),
        isEmpty,
        reason: 'the stored .epub copy is removed after conversion',
      );
    });

    test('orders pages by spine order, not filename order', () async {
      final book = await importFixture(
        await createFixedLayoutMangaEpub(
          imageNames: ['c.png', 'a.png', 'b.png'],
        ),
      );

      final converted = await repo.convertEpubToManga(book);
      final cache = await readPagesCache(converted.filePath);

      // Spine page 0 is c.png (10x100); an alphabetical sort would put
      // a.png (11x101) first.
      expect(
        cache.pages.map((pg) => '${pg.imgWidth}x${pg.imgHeight}'),
        ['10x100', '11x101', '12x102'],
        reason: 'spine order must win over filename order',
      );
    });

    test('resolves SVG-wrapped images via xlink:href', () async {
      final book = await importFixture(
        await createFixedLayoutMangaEpub(pageCount: 3, svgWrapped: true),
      );

      final converted = await repo.convertEpubToManga(book);

      expect(converted.bookType, 'manga');
      expect((await readPagesCache(converted.filePath)).pages, hasLength(3));
    });

    test(
      'resolves image refs against the XHTML doc dir, not the OPF dir',
      () async {
        final book = await importFixture(
          await createFixedLayoutMangaEpub(pageCount: 3, nestedImageDir: true),
        );

        final converted = await repo.convertEpubToManga(book);

        expect((await readPagesCache(converted.filePath)).pages, hasLength(3));
      },
    );

    test('decodes URL-encoded hrefs', () async {
      final book = await importFixture(
        await createFixedLayoutMangaEpub(
          imageNames: ['表紙 1.png', '本文 2.png', '本文 3.png'],
          urlEncodedHrefs: true,
        ),
      );

      final converted = await repo.convertEpubToManga(book);

      expect((await readPagesCache(converted.filePath)).pages, hasLength(3));
    });

    test(
      'deduplicates a cover page that reuses the first page image',
      () async {
        final book = await importFixture(
          await createFixedLayoutMangaEpub(
            pageCount: 4,
            coverPageReusesFirstImage: true,
          ),
        );

        final converted = await repo.convertEpubToManga(book);

        expect(converted.totalPages, 4);
        expect((await readPagesCache(converted.filePath)).pages, hasLength(4));
      },
    );

    test('rejects a text EPUB and leaves it untouched', () async {
      final book = await importFixture(await createTestEpub());
      final contentDir = book.filePath;

      await expectLater(
        repo.convertEpubToManga(book),
        throwsA(isA<EpubNotMangaException>()),
      );

      final after = (await repo.getBookById(book.id))!;
      expect(after.bookType, 'epub');
      expect(after.filePath, contentDir);
      expect(Directory(contentDir).existsSync(), isTrue);
      expect(
        Directory(p.join(p.dirname(contentDir), 'images')).existsSync(),
        isFalse,
      );
    });

    test('tolerates up to 10% non-image spine docs', () async {
      final book = await importFixture(
        await createFixedLayoutMangaEpub(pageCount: 10, textOnlyPages: 1),
      );

      final converted = await repo.convertEpubToManga(book);

      expect(converted.totalPages, 10, reason: 'text pages are skipped');
    });

    test('rejects a book where half the spine docs are text', () async {
      final book = await importFixture(
        await createFixedLayoutMangaEpub(pageCount: 5, textOnlyPages: 5),
      );

      await expectLater(
        repo.convertEpubToManga(book),
        throwsA(isA<EpubNotMangaException>()),
      );
      expect((await repo.getBookById(book.id))!.bookType, 'epub');
    });

    test('throws when the extracted content directory is missing', () async {
      final book = await importFixture(await createFixedLayoutMangaEpub());
      Directory(book.filePath).deleteSync(recursive: true);

      await expectLater(repo.convertEpubToManga(book), throwsA(anything));
      expect((await repo.getBookById(book.id))!.bookType, 'epub');
    });

    test('rolls back moved images when a rename fails mid-way', () async {
      final book = await importFixture(
        await createFixedLayoutMangaEpub(pageCount: 3),
      );
      final bookDir = p.dirname(book.filePath);
      // A directory squatting on the second target name makes that rename
      // fail after the first one has already succeeded.
      Directory(
        p.join(bookDir, 'images', '0002.png'),
      ).createSync(recursive: true);

      await expectLater(repo.convertEpubToManga(book), throwsA(anything));

      final after = (await repo.getBookById(book.id))!;
      expect(after.bookType, 'epub');
      expect(
        Directory(p.join(bookDir, 'images')).existsSync(),
        isFalse,
        reason: 'rollback removes the images directory',
      );
      final contentImages = Directory(
        p.join(book.filePath, 'OEBPS', 'images'),
      ).listSync().whereType<File>();
      expect(
        contentImages,
        hasLength(3),
        reason: 'every source image is restored into content/',
      );
    });
  });
}
