import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/data/services/mokuro_parser.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('mokuro_parser_malformed_');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  Future<String> writeMokuroFile(Map<String, dynamic> json) async {
    final path = p.join(root.path, 'Volume.mokuro');
    await File(path).writeAsString(jsonEncode(json));
    return path;
  }

  Map<String, dynamic> pageJson({
    String imgPath = '0001.jpg',
    Object? blocks = const [],
  }) => {
    'img_path': imgPath,
    'img_width': 1000,
    'img_height': 1500,
    'blocks': blocks,
  };

  test(
    'import survives a block with null lines_coords (MEKURU-12 regression)',
    () async {
      final path = await writeMokuroFile({
        'version': '0.2.1',
        'title': 'Volume',
        'volume': 'Volume',
        'pages': [
          pageJson(
            blocks: [
              {
                'box': [10, 20, 110, 220],
                'vertical': true,
                'font_size': 24,
                'lines_coords': null,
                'lines': ['こんにちは'],
              },
            ],
          ),
        ],
      });

      final (manifest, pages) = await MokuroParser.parseMokuroFile(path);

      expect(pages, hasLength(1));
      expect(pages.first.blocks, hasLength(1));
      expect(pages.first.blocks.first.lines, ['こんにちは']);
      expect(pages.first.blocks.first.linesCoords, isEmpty);
      expect(manifest.imageFileNames, ['0001.jpg']);
    },
  );

  test('skips page entries missing img_path or dimensions', () async {
    final path = await writeMokuroFile({
      'title': 'Volume',
      'volume': 'Volume',
      'pages': [
        pageJson(imgPath: '0001.jpg'),
        {'img_width': 1000, 'img_height': 1500, 'blocks': []},
        {'img_path': '0003.jpg', 'blocks': []},
        'not a map',
        pageJson(imgPath: '0005.jpg'),
      ],
    });

    final (manifest, pages) = await MokuroParser.parseMokuroFile(path);

    expect(pages, hasLength(2));
    expect(manifest.imageFileNames, ['0001.jpg', '0005.jpg']);
    expect(pages.map((page) => page.pageIndex), [0, 1]);
  });

  test('treats null blocks as an empty page and accepts double dimensions',
      () async {
    final path = await writeMokuroFile({
      'title': 'Volume',
      'volume': 'Volume',
      'pages': [
        {
          'img_path': '0001.jpg',
          'img_width': 1000.0,
          'img_height': 1500.0,
          'blocks': null,
        },
      ],
    });

    final (_, pages) = await MokuroParser.parseMokuroFile(path);

    expect(pages, hasLength(1));
    expect(pages.first.blocks, isEmpty);
    expect(pages.first.imgWidth, 1000);
    expect(pages.first.imgHeight, 1500);
  });

  test('skips non-map entries inside a page blocks list', () async {
    final path = await writeMokuroFile({
      'title': 'Volume',
      'volume': 'Volume',
      'pages': [
        pageJson(
          blocks: [
            null,
            'garbage',
            {
              'box': [1, 2, 3, 4],
              'vertical': false,
              'font_size': 12,
              'lines_coords': [],
              'lines': ['テキスト'],
            },
          ],
        ),
      ],
    });

    final (_, pages) = await MokuroParser.parseMokuroFile(path);

    expect(pages.first.blocks, hasLength(1));
    expect(pages.first.blocks.first.lines, ['テキスト']);
  });
}
