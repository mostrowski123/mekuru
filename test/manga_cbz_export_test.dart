import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/data/services/manga_cbz_export.dart';

/// Minimal bytes that pass filename filtering without being a real image.
final fakeJpegBytes = [0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0];

void main() {
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('manga_cbz_export_test_');
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  /// Write a manga cache dir with [pages] and matching image files.
  Future<String> createCacheDir(List<MokuroPage> pages) async {
    final cacheDir = Directory('${tmpDir.path}/cache')..createSync();
    final imageDir = Directory('${cacheDir.path}/images')..createSync();
    for (final page in pages) {
      File(
        '${imageDir.path}/${page.imageFileName}',
      ).writeAsBytesSync(fakeJpegBytes);
    }
    final book = MokuroBook(
      title: 'テスト本',
      imageDirPath: imageDir.path,
      ocrSource: 'mokuro',
      ocrCompleted: true,
      pages: pages,
    );
    File(
      '${cacheDir.path}/$mangaPagesCacheFileName',
    ).writeAsStringSync(jsonEncode(book.toJson()));
    return cacheDir.path;
  }

  Archive readZip(String path) =>
      ZipDecoder().decodeBytes(File(path).readAsBytesSync());

  const block = MokuroTextBlock(
    box: [10.0, 20.0, 110.0, 220.0],
    vertical: true,
    fontSize: 24.0,
    linesCoords: [
      [
        [10.0, 20.0],
        [110.0, 20.0],
        [110.0, 220.0],
        [10.0, 220.0],
      ],
    ],
    lines: ['こんにちは'],
  );

  test(
    'embeds a .mokuro entry with remapped filenames for OCR books',
    () async {
      final cacheDirPath = await createCacheDir([
        const MokuroPage(
          pageIndex: 0,
          imageFileName: 'cover_a.png',
          imgWidth: 800,
          imgHeight: 1200,
          blocks: [block],
        ),
        const MokuroPage(
          pageIndex: 1,
          imageFileName: 'page_b.jpg',
          imgWidth: 800,
          imgHeight: 1200,
          blocks: [],
        ),
      ]);

      final outPath = '${tmpDir.path}/exported.cbz';
      final written = await writeCbz(cacheDirPath, outPath);
      expect(written, 2);

      final archive = readZip(outPath);
      final names = archive.files.map((f) => f.name).toList();
      expect(names, containsAll(['0001.png', '0002.jpg', 'exported.mokuro']));

      final manifest =
          jsonDecode(
                utf8.decode(
                  archive.files
                      .firstWhere((f) => f.name == 'exported.mokuro')
                      .content,
                ),
              )
              as Map<String, dynamic>;
      expect(manifest['title'], 'テスト本');
      final pages = manifest['pages'] as List;
      expect(pages, hasLength(2));
      final first = pages[0] as Map<String, dynamic>;
      expect(first['img_path'], '0001.png');
      expect(first['img_width'], 800);
      expect(first['img_height'], 1200);
      final blocks = first['blocks'] as List;
      expect(blocks, hasLength(1));
      final ocrBlock = blocks[0] as Map<String, dynamic>;
      expect(ocrBlock['box'], [10.0, 20.0, 110.0, 220.0]);
      expect(ocrBlock['vertical'], true);
      expect(ocrBlock['font_size'], 24.0);
      expect(ocrBlock['lines'], ['こんにちは']);
      expect(ocrBlock['lines_coords'], isNotEmpty);
      // Device-derived word segmentation must not leak into the manifest.
      expect(ocrBlock.containsKey('words'), isFalse);
      expect((pages[1] as Map<String, dynamic>)['blocks'], isEmpty);
    },
  );

  test('round-trips through MokuroTextBlock.fromOcrJson', () async {
    final decoded = MokuroTextBlock.fromOcrJson(
      jsonDecode(jsonEncode(block.toOcrJson())) as Map<String, dynamic>,
    );
    expect(decoded.box, block.box);
    expect(decoded.vertical, block.vertical);
    expect(decoded.fontSize, block.fontSize);
    expect(decoded.linesCoords, block.linesCoords);
    expect(decoded.lines, block.lines);
  });

  test('books without OCR data export images-only', () async {
    final cacheDirPath = await createCacheDir([
      const MokuroPage(
        pageIndex: 0,
        imageFileName: 'page_a.jpg',
        imgWidth: 800,
        imgHeight: 1200,
        blocks: [],
      ),
    ]);

    final outPath = '${tmpDir.path}/plain.cbz';
    await writeCbz(cacheDirPath, outPath);

    final names = readZip(outPath).files.map((f) => f.name).toList();
    expect(names, ['0001.jpg']);
  });
}
