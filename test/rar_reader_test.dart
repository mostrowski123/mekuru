import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart' show getCrc32;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rar_reader/rar_reader.dart';

import 'shared/rar_fixtures.dart';

/// Expected names and contents come from libarchive's own tests of these
/// archives (libarchive/test/test_read_format_rar*.c).
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('rar_reader_test');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  String write(List<int> bytes, [String name = 'book.cbr']) {
    final file = File(p.join(dir.path, name))..writeAsBytesSync(bytes);
    return file.path;
  }

  group('RarReader', skip: rarSkip, () {
    test('reads a RAR 4 archive, folders and links as non-files', () {
      final entries = readRar(write(rar4Basic));

      expect(entries.keys, [
        'test.txt',
        'testlink',
        'testdir/test.txt',
        'testdir',
        'testemptydir',
      ]);
      expect(utf8.decode(entries['test.txt']!), 'test text document\r\n');
      expect(
        utf8.decode(entries['testdir/test.txt']!),
        'test text document\r\n',
      );
      expect(entries['testlink'], isNull);
      expect(entries['testdir'], isNull);
    });

    test('decompresses a compressed RAR 4 archive', () {
      final entries = readRar(write(rar4CompressNormal));

      final html = entries['LibarchiveAddingTest.html']!;
      expect(html, hasLength(20111));
      expect(utf8.decode(html), endsWith('</BODY>\n</HTML>'));
      expect(entries['testdir/LibarchiveAddingTest.html'], html);
    });

    test('reads Japanese RAR 4 names as UTF-8', () {
      final entries = readRar(write(rar4Unicode));

      expect(entries.keys, contains('abcdefghijklmnopqrsテスト.txt'));
      final kanji = entries.entries.singleWhere(
        (e) => e.key.endsWith('漢字長いファイル名long-filename-in-漢字.txt'),
      );
      expect(utf8.decode(kanji.value!), 'kanji');
    });

    test('decompresses a solid RAR 5 archive in order', () {
      final entries = readRar(write(rar5Solid));

      expect(entries.keys, [
        'test.bin',
        for (var i = 1; i <= 6; i++) 'test$i.bin',
      ]);
      expect(getCrc32(entries['test.bin']!), 0x7CCA70CD);
      expect(getCrc32(entries['test1.bin']!), 0x7E13B2C6);
      expect(getCrc32(entries['test6.bin']!), 0x36A448FF);
    });

    test('reads the archives storedRar5 writes', () {
      final page = List.generate(300000, (i) => i % 251);
      final entries = readRar(
        write(
          storedRar5({
            'vol1/001.png': page,
            '表紙.jpg': [1, 2, 3],
          }),
        ),
      );

      expect(entries.keys, ['vol1/001.png', '表紙.jpg']);
      expect(entries['vol1/001.png'], page);
      expect(entries['表紙.jpg'], [1, 2, 3]);
    });

    test('reports the bytes consumed so far', () {
      final path = write(rar5MultipleFiles);
      final reader = RarReader.open(path);
      addTearDown(reader.close);

      var last = reader.bytesConsumed;
      for (var e = reader.nextEntry(); e != null; e = reader.nextEntry()) {
        reader.readEntry();
        expect(reader.bytesConsumed, greaterThan(last));
        last = reader.bytesConsumed;
      }
      expect(last, lessThanOrEqualTo(File(path).lengthSync()));
    });

    for (final (label, archive) in [
      ('RAR 4', rar4Encrypted),
      ('RAR 5', rar5Encrypted),
    ]) {
      test('$label: lists encrypted entries, throws on reading one', () {
        final reader = RarReader.open(write(archive));
        addTearDown(reader.close);

        final a = reader.nextEntry()!;
        expect((a.name, a.isEncrypted), ('a.txt', false));
        expect(utf8.decode(reader.readEntry()), 'This is from a.txt');
        final b = reader.nextEntry()!;
        expect((b.name, b.isEncrypted), ('b.txt', true));
        expect(reader.readEntry, throwsA(isA<RarEncryptedException>()));
        expect(reader.nextEntry()!.name, 'c.txt');
      });
    }

    test('throws RarEncryptedException for encrypted file names', () {
      final reader = RarReader.open(write(rar4EncryptedHeaders));
      addTearDown(reader.close);

      expect(reader.nextEntry, throwsA(isA<RarEncryptedException>()));
    });

    test('rejects a solid RAR 4 archive when opening it', () {
      expect(
        () => RarReader.open(write(markRar4Solid(rar4Basic))),
        throwsA(isA<RarSolidUnsupportedException>()),
      );
    });

    test('throws RarException for a truncated archive', () {
      expect(
        () => readRar(write(rar5Solid.sublist(0, 600))),
        throwsA(isA<RarException>()),
      );
    });

    test('throws RarException for a file that is not a RAR', () {
      expect(
        () => readRar(write(utf8.encode('Rar! but not really'))),
        throwsA(isA<RarException>()),
      );
    });
  });

  test('isRar recognises RAR 4 and RAR 5 signatures only', () {
    expect(RarReader.isRar(rar4Basic), isTrue);
    expect(RarReader.isRar(rar5Solid), isTrue);
    expect(RarReader.isRar(const [0x50, 0x4B, 0x03, 0x04, 0, 0]), isFalse);
    expect(RarReader.isRar(const [0x52, 0x61]), isFalse);
  });
}
