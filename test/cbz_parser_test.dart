import 'dart:io';

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

  group('CbzParser.readImageDimensions', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('cbz_dims_test_');
    });

    tearDown(() {
      tmpDir.deleteSync(recursive: true);
    });

    test('returns width and height for a valid image', () async {
      final image = img.Image(width: 12, height: 34);
      final imagePath = '${tmpDir.path}/page.png';
      await File(imagePath).writeAsBytes(img.encodePng(image));

      final dims = await CbzParser.readImageDimensions(imagePath);

      expect(dims, isNotNull);
      expect(dims!.width, 12);
      expect(dims.height, 34);
    });

    test('returns null for invalid image data', () async {
      final imagePath = '${tmpDir.path}/invalid.jpg';
      await File(imagePath).writeAsBytes([1, 2, 3, 4]);

      final dims = await CbzParser.readImageDimensions(imagePath);

      expect(dims, isNull);
    });
  });
}
