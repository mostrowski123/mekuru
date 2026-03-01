import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/data/services/mokuro_parser.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'parseSingleHtmlFile uses SAF-selected filename stem instead of temp file stem',
    () async {
      final root = await Directory.systemTemp.createTemp('mokuro_parser_test_');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });

      final parentDir = Directory(p.join(root.path, 'library'));
      final imageDir = Directory(p.join(parentDir.path, 'BookName'));
      final ocrDir = Directory(p.join(parentDir.path, '_ocr', 'BookName'));
      await imageDir.create(recursive: true);
      await ocrDir.create(recursive: true);

      // HTML is intentionally copied to a temporary path with a mismatched name
      // to simulate Android folder-first SAF import behavior.
      final tempHtmlPath = p.join(root.path, 'manga_import_17772378004275888.html');
      await File(tempHtmlPath).writeAsString('''
<html>
  <head><title>Book Name | mokuro</title></head>
  <body>
    <div style="background-image:url(&quot;BookName/0001.jpg&quot;)"></div>
  </body>
</html>
''');

      final result = await MokuroParser.parseSingleHtmlFile(
        tempHtmlPath,
        originalDirPath: parentDir.path,
        safSelectedFileRelativePath: 'BookName.html',
      );

      expect(result.$1.imageDirPath, p.join(parentDir.path, 'BookName'));
      expect(result.$1.ocrDirPath, p.join(parentDir.path, '_ocr', 'BookName'));
      expect(result.$1.imageFileNames, ['0001.jpg']);
      expect(result.$2.length, 1);
      expect(result.$2.first.imageFileName, '0001.jpg');
    },
  );
}
