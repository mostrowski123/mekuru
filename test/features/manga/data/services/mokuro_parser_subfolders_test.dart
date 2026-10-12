import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/data/services/mokuro_parser.dart';
import 'package:path/path.dart' as p;

/// mokuro writes each page's path relative to the volume folder, chapter
/// folders included (`ch1/001.jpg`); pages keep that path.
void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('mokuro_subfolders_');
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  void writePage(String relativePath) =>
      File(p.joinAll([root.path, ...relativePath.split('/')]))
        ..createSync(recursive: true)
        ..writeAsBytesSync(const [0xFF, 0xD8, 0xFF]);

  Future<String> writeMokuro(List<String> imgPaths) async {
    final path = p.join(root.path, 'Vol.mokuro');
    await File(path).writeAsString(
      jsonEncode({
        'version': '0.2.5',
        'title': 'Vol',
        'volume': 'Vol',
        'pages': [
          for (final imgPath in imgPaths)
            {
              'img_path': imgPath,
              'img_width': 10,
              'img_height': 20,
              'blocks': [],
            },
        ],
      }),
    );
    return path;
  }

  test('pages in chapter folders keep their folder', () async {
    writePage('Vol/ch1/001.jpg');
    writePage('Vol/ch2/001.jpg');

    final (manifest, pages) = await MokuroParser.parseMokuroFile(
      await writeMokuro(['ch1/001.jpg', 'ch2/001.jpg']),
    );

    expect(manifest.imageDirPath, p.join(root.path, 'Vol'));
    expect(pages.map((page) => page.imageFileName), [
      'ch1/001.jpg',
      'ch2/001.jpg',
    ]);
  });

  test('an img_path that names the volume folder finds its pages', () async {
    writePage('Vol/0001.jpg');

    final (manifest, pages) = await MokuroParser.parseMokuroFile(
      await writeMokuro(['Vol/0001.jpg']),
    );

    expect(
      File(
        p.join(manifest.imageDirPath, pages.single.imageFileName),
      ).existsSync(),
      isTrue,
    );
  });

  test('Windows separators are normalised; paths out of the folder are '
      'cut to their file name', () async {
    writePage('Vol/ch1/001.jpg');

    final (_, pages) = await MokuroParser.parseMokuroFile(
      await writeMokuro([r'ch1\001.jpg', '../../etc/002.jpg', '/abs/003.jpg']),
    );

    expect(pages.map((page) => page.imageFileName), [
      'ch1/001.jpg',
      '002.jpg',
      '003.jpg',
    ]);
  });

  test('legacy HTML keeps chapter folders and finds their OCR', () async {
    writePage('Book/ch1/0001.jpg');
    File(p.join(root.path, '_ocr', 'Book', 'ch1', '0001.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'img_width': 10,
          'img_height': 20,
          'blocks': [
            {
              'box': [1, 2, 3, 4],
              'vertical': true,
              'font_size': 12,
              'lines_coords': null,
              'lines': ['漢字'],
            },
          ],
        }),
      );
    final html = p.join(root.path, 'Book.html');
    await File(html).writeAsString(
      '<div style="background-image:url(&quot;Book/ch1/0001.jpg&quot;)">'
      '</div>',
    );

    final (manifest, pages) = await MokuroParser.parseSingleHtmlFile(html);

    expect(manifest.imageDirPath, p.join(root.path, 'Book'));
    expect(pages.single.imageFileName, 'ch1/0001.jpg');
    expect(pages.single.blocks.single.lines, ['漢字']);
  });
}
