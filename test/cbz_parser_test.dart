import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mekuru/features/manga/data/services/cbz_parser.dart';

/// Minimal bytes that won't decode as a real image but pass filename filtering.
List<int> get fakeJpegBytes => [0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0];

void main() {
  group('CbzParser.extract', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('cbz_parser_test_');
    });

    tearDown(() {
      tmpDir.deleteSync(recursive: true);
    });

    /// Create a CBZ (ZIP) file in [dir] with the given [entries].
    /// Each entry is a map of filename → content bytes.
    Future<String> createCbz(
      String name,
      Map<String, List<int>> entries,
    ) async {
      final archive = Archive();
      for (final entry in entries.entries) {
        archive.addFile(
          ArchiveFile(entry.key, entry.value.length, entry.value),
        );
      }
      final encoded = ZipEncoder().encode(archive);
      final cbzPath = '${tmpDir.path}/$name.cbz';
      await File(cbzPath).writeAsBytes(encoded);
      return cbzPath;
    }

    test('extracts images and returns sorted filenames', () async {
      final cbzPath = await createCbz('test_manga', {
        'page_003.jpg': fakeJpegBytes,
        'page_001.jpg': fakeJpegBytes,
        'page_002.jpg': fakeJpegBytes,
      });

      final outputDir = '${tmpDir.path}/output';
      final metadata = await CbzParser.extract(cbzPath, outputDir);

      expect(metadata.title, 'test_manga');
      expect(metadata.imageFileNames, [
        'page_001.jpg',
        'page_002.jpg',
        'page_003.jpg',
      ]);
      expect(metadata.coverImagePath, contains('page_001.jpg'));
    });

    test('skips non-image files', () async {
      final cbzPath = await createCbz('mixed_content', {
        'page_01.jpg': fakeJpegBytes,
        'ComicInfo.xml': [0x3C], // <
        'thumbs.db': [0x00],
        'page_02.png': fakeJpegBytes,
      });

      final outputDir = '${tmpDir.path}/output';
      final metadata = await CbzParser.extract(cbzPath, outputDir);

      expect(metadata.imageFileNames, ['page_01.jpg', 'page_02.png']);
    });

    test('skips files whose basename starts with dot', () async {
      final cbzPath = await createCbz('with_hidden', {
        '.DS_Store': [0x00],
        '.hidden_image.jpg': fakeJpegBytes,
        'page_01.jpg': fakeJpegBytes,
      });

      final outputDir = '${tmpDir.path}/output';
      final metadata = await CbzParser.extract(cbzPath, outputDir);

      expect(metadata.imageFileNames, ['page_01.jpg']);
    });

    test('handles nested directory structure', () async {
      final cbzPath = await createCbz('nested', {
        'chapter1/page_01.jpg': fakeJpegBytes,
        'chapter1/page_02.jpg': fakeJpegBytes,
      });

      final outputDir = '${tmpDir.path}/output';
      final metadata = await CbzParser.extract(cbzPath, outputDir);

      // Images from nested dirs are flattened using basename.
      expect(metadata.imageFileNames.length, 2);
    });

    test('uses natural sort for filenames with numbers', () async {
      final cbzPath = await createCbz('natural_sort', {
        'page_10.jpg': fakeJpegBytes,
        'page_2.jpg': fakeJpegBytes,
        'page_1.jpg': fakeJpegBytes,
        'page_20.jpg': fakeJpegBytes,
      });

      final outputDir = '${tmpDir.path}/output';
      final metadata = await CbzParser.extract(cbzPath, outputDir);

      expect(metadata.imageFileNames, [
        'page_1.jpg',
        'page_2.jpg',
        'page_10.jpg',
        'page_20.jpg',
      ]);
    });

    test('handles empty archive', () async {
      final cbzPath = await createCbz('empty', {});

      final outputDir = '${tmpDir.path}/output';
      final metadata = await CbzParser.extract(cbzPath, outputDir);

      expect(metadata.imageFileNames, isEmpty);
      expect(metadata.coverImagePath, isNull);
    });

    test('accepts various image extensions', () async {
      final cbzPath = await createCbz('extensions', {
        'page.jpg': fakeJpegBytes,
        'page.jpeg': fakeJpegBytes,
        'page.png': fakeJpegBytes,
        'page.gif': fakeJpegBytes,
        'page.webp': fakeJpegBytes,
        'page.bmp': fakeJpegBytes,
        'page.tiff': fakeJpegBytes,
        'page.tif': fakeJpegBytes,
      });

      final outputDir = '${tmpDir.path}/output';
      final metadata = await CbzParser.extract(cbzPath, outputDir);

      expect(metadata.imageFileNames.length, 8);
    });

    test('title is derived from CBZ filename', () async {
      final cbzPath = await createCbz('My Awesome Manga Vol.3', {
        'page.jpg': fakeJpegBytes,
      });

      final outputDir = '${tmpDir.path}/output';
      final metadata = await CbzParser.extract(cbzPath, outputDir);

      expect(metadata.title, 'My Awesome Manga Vol.3');
    });

    test('handles duplicate filenames from different subdirectories', () async {
      final cbzPath = await createCbz('dupes', {
        'chapter1/page_01.jpg': fakeJpegBytes,
        'chapter2/page_01.jpg': fakeJpegBytes,
      });

      final outputDir = '${tmpDir.path}/output';
      final metadata = await CbzParser.extract(cbzPath, outputDir);

      // The second file should get prefixed to avoid collision.
      expect(metadata.imageFileNames.length, 2);
      expect(metadata.imageFileNames.toSet().length, 2); // all unique
    });

    test(
      'avoids prefixed duplicate collisions with existing flattened names',
      () async {
        final cbzPath = await createCbz('dupe_prefix_collision', {
          'b_page_01.jpg': fakeJpegBytes,
          'a/page_01.jpg': fakeJpegBytes,
          'b/page_01.jpg': fakeJpegBytes,
        });

        final outputDir = '${tmpDir.path}/output';
        final metadata = await CbzParser.extract(cbzPath, outputDir);

        expect(metadata.imageFileNames.length, 3);
        expect(metadata.imageFileNames.toSet().length, 3);
      },
    );
  });

  group('CbzParser image extension filtering', () {
    // Test the _isImageFile static method indirectly through extract behavior.
    // The logic is: files with image extensions are included, others are not.
    // We've already tested this above, but let's add edge cases.

    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('cbz_ext_test_');
    });

    tearDown(() {
      tmpDir.deleteSync(recursive: true);
    });

    test('rejects txt and xml files', () async {
      final archive = Archive();
      archive.addFile(ArchiveFile('readme.txt', 4, [0, 0, 0, 0]));
      archive.addFile(ArchiveFile('metadata.xml', 4, [0, 0, 0, 0]));
      archive.addFile(
        ArchiveFile('page.jpg', 8, [0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0]),
      );
      final encoded = ZipEncoder().encode(archive);
      final cbzPath = '${tmpDir.path}/test.cbz';
      await File(cbzPath).writeAsBytes(encoded);

      final outputDir = '${tmpDir.path}/output';
      final metadata = await CbzParser.extract(cbzPath, outputDir);

      expect(metadata.imageFileNames, ['page.jpg']);
    });

    test('case-insensitive extension matching', () async {
      final archive = Archive();
      archive.addFile(
        ArchiveFile('page.JPG', 8, [0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0]),
      );
      archive.addFile(
        ArchiveFile('page2.Png', 8, [0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0]),
      );
      final encoded = ZipEncoder().encode(archive);
      final cbzPath = '${tmpDir.path}/test.cbz';
      await File(cbzPath).writeAsBytes(encoded);

      final outputDir = '${tmpDir.path}/output';
      final metadata = await CbzParser.extract(cbzPath, outputDir);

      // Should accept .JPG and .Png (case-insensitive).
      expect(metadata.imageFileNames.length, 2);
    });
  });

  group('readImageDimensionsFromBytes', () {
    Uint8List encoded(
      List<int> Function(img.Image) encode, {
      int width = 12,
      int height = 34,
    }) => Uint8List.fromList(encode(img.Image(width: width, height: height)));

    test('reads JPEG dimensions', () {
      final dims = readImageDimensionsFromBytes(encoded(img.encodeJpg));
      expect([dims?.width, dims?.height], [12, 34]);
    });

    test('reads PNG dimensions', () {
      final dims = readImageDimensionsFromBytes(encoded(img.encodePng));
      expect([dims?.width, dims?.height], [12, 34]);
    });

    test('reads formats without a direct parser via the fallback', () {
      // GIF and BMP go through the image package's header decode.
      for (final encode in [img.encodeGif, img.encodeBmp]) {
        final dims = readImageDimensionsFromBytes(encoded(encode));
        expect([dims?.width, dims?.height], [12, 34]);
      }
    });

    test('reads a JPEG without decoding its pixel data', () {
      // Truncated past the SOF header, so no scan data remains. A full decode
      // cannot succeed; reading the size must still work. This is the whole
      // point — img.decodeImage here costs ~31ms on a 1600x2300 page because
      // it allocates the entire coefficient buffer just to expose width and
      // height, which is what made CBZ import take minutes.
      final full = encoded(img.encodeJpg, width: 640, height: 480);
      final headerOnly = Uint8List.sublistView(full, 0, full.length ~/ 4);

      expect(
        () => img.decodeImage(headerOnly),
        throwsA(anything),
        reason: 'guard: a full decode must fail on this truncated input',
      );

      final dims = readImageDimensionsFromBytes(headerOnly);
      expect([dims?.width, dims?.height], [640, 480]);
    });

    test('returns null rather than throwing on unusable bytes', () {
      for (final bytes in [
        <int>[],
        [1, 2, 3, 4],
        [0xFF, 0xD8], // JPEG magic with no frame header
        [0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0], // the test fixture bytes
      ]) {
        expect(readImageDimensionsFromBytes(Uint8List.fromList(bytes)), isNull);
      }
    });
  });

  group('CbzParser.extract page dimensions', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('cbz_dims_test_');
    });

    tearDown(() {
      tmpDir.deleteSync(recursive: true);
    });

    Future<String> createCbz(
      String name,
      Map<String, List<int>> entries,
    ) async {
      final archive = Archive();
      for (final entry in entries.entries) {
        archive.addFile(
          ArchiveFile(entry.key, entry.value.length, entry.value),
        );
      }
      final cbzPath = '${tmpDir.path}/$name.cbz';
      await File(cbzPath).writeAsBytes(ZipEncoder().encode(archive));
      return cbzPath;
    }

    List<int> png(int width, int height) =>
        img.encodePng(img.Image(width: width, height: height));

    test('reports dimensions per page during extraction', () async {
      // Dimensions come from the bytes already in hand while extracting, so
      // importing never re-reads the pages back off disk.
      final cbzPath = await createCbz('sized', {
        'page_1.png': png(100, 200),
        'page_2.png': png(300, 400),
      });

      final metadata = await CbzParser.extract(cbzPath, '${tmpDir.path}/out');

      expect(metadata.imageFileNames, ['page_1.png', 'page_2.png']);
      expect(metadata.dimensionsOf('page_1.png')?.width, 100);
      expect(metadata.dimensionsOf('page_1.png')?.height, 200);
      expect(metadata.dimensionsOf('page_2.png')?.width, 300);
      expect(metadata.dimensionsOf('page_2.png')?.height, 400);
    });

    test('yields null dimensions for pages that cannot be parsed', () async {
      final cbzPath = await createCbz('mixed', {
        'good.png': png(10, 20),
        'bad.jpg': fakeJpegBytes,
      });

      final metadata = await CbzParser.extract(cbzPath, '${tmpDir.path}/out');

      expect(metadata.imageFileNames, hasLength(2));
      expect(metadata.dimensionsOf('good.png')?.width, 10);
      expect(metadata.dimensionsOf('bad.jpg'), isNull);
    });

    test('reports extraction progress across the whole run', () async {
      final cbzPath = await createCbz('progress', {
        'a.png': png(8, 8),
        'b.png': png(8, 8),
        'c.png': png(8, 8),
        'd.png': png(8, 8),
      });
      final progress = <double>[];

      await CbzParser.extract(
        cbzPath,
        '${tmpDir.path}/out',
        onProgress: progress.add,
      );

      expect(progress, [0.25, 0.5, 0.75, 1.0]);
    });
  });
}
