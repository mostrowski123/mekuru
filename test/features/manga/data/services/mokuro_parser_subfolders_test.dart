import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
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

  // A folder with another name used to import as a book with no readable
  // pages.
  final missingImages = throwsA(
    isA<MangaImagesMissingException>().having(
      (e) => e.folderName,
      'folderName',
      'Vol',
    ),
  );

  test('a .mokuro whose page images are in no folder it looks in is '
      'refused', () async {
    writePage('renamed/0001.jpg');

    await expectLater(
      MokuroParser.parseMokuroFile(await writeMokuro(['0001.jpg'])),
      missingImages,
    );
  });

  test('a volume missing only its first page keeps its folder', () async {
    writePage('Vol/0002.jpg');

    final (manifest, _) = await MokuroParser.parseMokuroFile(
      await writeMokuro(['0001.jpg', '0002.jpg']),
    );

    expect(manifest.imageDirPath, p.join(root.path, 'Vol'));
  });

  group('in an Android folder', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('mekuru/android_saf');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    /// Answers the folder channel as a picked folder holding [files].
    void stubFolder(Set<String> files) =>
        messenger.setMockMethodCallHandler(channel, (call) async {
          final path = (call.arguments as Map)['relativePath'] as String;
          return switch (call.method) {
            'existsInTreePath' => files.contains(path),
            'getDocumentUriInTree' =>
              files.any((file) => file == path || file.startsWith('$path/'))
                  ? 'content://tree/abc/document/$path'
                  : null,
            _ => null,
          };
        });

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('a .mokuro finds its pages in the volume folder', () async {
      stubFolder({'Vol/0001.jpg'});

      final (manifest, _) = await MokuroParser.parseMokuroFile(
        await writeMokuro(['0001.jpg']),
        safTreeUri: 'content://tree/abc',
        safSelectedFileRelativePath: 'Vol.mokuro',
      );

      expect(manifest.safImageDirRelativePath, 'Vol');
    });

    test('a .mokuro missing only its first page keeps its folder', () async {
      stubFolder({'Vol/0002.jpg'});

      final (manifest, _) = await MokuroParser.parseMokuroFile(
        await writeMokuro(['0001.jpg', '0002.jpg']),
        safTreeUri: 'content://tree/abc',
        safSelectedFileRelativePath: 'Vol.mokuro',
      );

      expect(manifest.safImageDirRelativePath, 'Vol');
    });

    // Android reads a temporary copy of the picked file.
    test('a .mokuro goes by the name of the file that was picked', () async {
      stubFolder({'Vol/0001.jpg'});
      final copy = p.join(root.path, 'manga_import_1.mokuro');
      await File(copy).writeAsString(
        jsonEncode({
          'pages': [
            {'img_path': '0001.jpg', 'img_width': 10, 'img_height': 20},
          ],
        }),
      );

      final (manifest, _) = await MokuroParser.parseMokuroFile(
        copy,
        safTreeUri: 'content://tree/abc',
        safSelectedFileRelativePath: 'Vol.mokuro',
      );

      expect(manifest.title, 'Vol');
      expect(manifest.safImageDirRelativePath, 'Vol');
    });

    test('a .mokuro whose page images are missing is refused', () async {
      stubFolder({'renamed/0001.jpg'});

      await expectLater(
        MokuroParser.parseMokuroFile(
          await writeMokuro(['0001.jpg']),
          safTreeUri: 'content://tree/abc',
          safSelectedFileRelativePath: 'Vol.mokuro',
        ),
        missingImages,
      );
    });

    Future<String> writeHtml() async {
      final html = p.join(root.path, 'Vol.html');
      await File(html).writeAsString(
        '<div style="background-image:url(&quot;Vol/0001.jpg&quot;)"></div>',
      );
      return html;
    }

    test('legacy HTML finds its pages in the folder it names', () async {
      stubFolder({'Vol/0001.jpg'});

      final (manifest, pages) = await MokuroParser.parseSingleHtmlFile(
        await writeHtml(),
        safTreeUri: 'content://tree/abc',
        safSelectedFileRelativePath: 'Vol.html',
      );

      expect(manifest.safImageDirRelativePath, 'Vol');
      expect(pages.single.imageFileName, '0001.jpg');
    });

    test('legacy HTML whose page images are missing is refused', () async {
      stubFolder({'renamed/0001.jpg'});

      await expectLater(
        MokuroParser.parseSingleHtmlFile(
          await writeHtml(),
          safTreeUri: 'content://tree/abc',
          safSelectedFileRelativePath: 'Vol.html',
        ),
        missingImages,
      );
    });
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
