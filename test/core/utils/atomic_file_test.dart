import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/utils/atomic_file.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('atomic_file_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  File fileIn(String name) => File('${tempDir.path}/$name');

  group('writeStringAtomic', () {
    test('creates a new file with the given contents', () async {
      final file = fileIn('new.json');

      await writeStringAtomic(file, '{"a":1}');

      expect(file.readAsStringSync(), '{"a":1}');
    });

    test('replaces an existing file', () async {
      final file = fileIn('existing.json');
      file.writeAsStringSync('old contents');

      await writeStringAtomic(file, 'new contents');

      expect(file.readAsStringSync(), 'new contents');
    });

    test('leaves no .tmp file behind on success', () async {
      final file = fileIn('clean.json');

      await writeStringAtomic(file, 'data');

      expect(File('${file.path}.tmp').existsSync(), isFalse);
    });

    test('writes UTF-8 Japanese text correctly', () async {
      final file = fileIn('japanese.json');

      await writeStringAtomic(file, '吾輩は猫である');

      expect(file.readAsStringSync(encoding: utf8), '吾輩は猫である');
    });
  });

  group('writeBytesAtomic', () {
    test('round-trips bytes exactly', () async {
      final file = fileIn('bytes.bin');
      final bytes = List<int>.generate(256, (i) => i);

      await writeBytesAtomic(file, bytes);

      expect(file.readAsBytesSync(), bytes);
    });

    test(
      'keeps original contents and cleans up .tmp when the write fails',
      () async {
        final file = fileIn('protected.bin');
        file.writeAsBytesSync([1, 2, 3]);
        // Make the tmp path unwritable by occupying it with a directory.
        Directory('${file.path}.tmp').createSync();

        await expectLater(
          writeBytesAtomic(file, [9, 9, 9]),
          throwsA(isA<FileSystemException>()),
        );

        expect(file.readAsBytesSync(), [1, 2, 3]);
      },
    );
  });
}
