import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart'
    show
        ArchiveFile,
        CompressionType,
        InputFileStream,
        ZipDecoder,
        ZipFileEncoder;
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/backup/data/services/full_backup_zip.dart';
import 'package:path/path.dart' as p;

import 'full_backup_zip_fixtures.dart';

/// Dart ports of the Kotlin `ZipNameMapperTest` and `ZipPeekTest`, plus the
/// writer and extractor the in-process job is built on.
void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('full_backup_zip_');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  group('ZipNameMapper', () {
    final mapper = ZipNameMapper({
      'Books/メロス/': 'book_1_abcdef12',
      'Manga/漫画': 'manga_2_00000000',
    });

    test('maps the archive layout back to the device layout', () {
      expect(mapper.map('Mekuru data/mekuru_db.sqlite'), 'mekuru_db.sqlite');
      expect(mapper.map('Mekuru data/settings.mekuru'), 'settings.mekuru');
      expect(
        mapper.map('Mekuru data/covers/custom_cover_1.jpg'),
        'books/custom_cover_1.jpg',
      );
      expect(mapper.map('Books/メロス/本.epub'), 'books/book_1_abcdef12/本.epub');
      expect(
        mapper.map('Books/メロス/content/ch1.xhtml'),
        'books/book_1_abcdef12/content/ch1.xhtml',
      );
      expect(mapper.map('Manga/漫画/001.jpg'), 'books/manga_2_00000000/001.jpg');
      expect(
        mapper.map('Manga/漫画/pages/001.jpg'),
        'books/manga_2_00000000/pages/001.jpg',
      );
      expect(
        mapper.map('Mekuru data/unidic-lite/sys.dic'),
        'unidic-lite/sys.dic',
      );
      expect(
        mapper.map('Mekuru data/unidic-lite/.install_complete'),
        'unidic-lite/.install_complete',
      );
    });

    test('skips sidecars and directories', () {
      expect(mapper.map('manifest.json'), isNull);
      expect(mapper.map('README.txt'), isNull);
      expect(mapper.map('Books/メロス/'), isNull);
      expect(mapper.map('Books/'), isNull);
      expect(mapper.map('Mekuru data/unidic-lite/'), isNull);
    });

    test('skips entries that belong nowhere', () {
      expect(mapper.map('Unknown/x.txt'), isNull);
      expect(mapper.map('Books/Other title/a.epub'), isNull);
      expect(mapper.map('Mekuru data/covers/nested/x.jpg'), isNull);
    });

    test('resolveInside refuses escapes', () {
      for (final evil in [
        '../evil.txt',
        '/abs.txt',
        'books/../../evil2.txt',
        r'books\..\..\evil3.txt',
        '..',
        '',
      ]) {
        expect(
          () => ZipNameMapper.resolveInside(tmp.path, evil),
          throwsA(isA<UnsafeZipEntryException>()),
          reason: evil,
        );
      }
      expect(
        ZipNameMapper.resolveInside(tmp.path, 'books/x/y.txt'),
        p.join(tmp.path, 'books', 'x', 'y.txt'),
      );
    });
  });

  group('peekZip', () {
    Future<File> archive() => buildArchive(File(p.join(tmp.path, 'a.zip')), [
      ('manifest.json', utf8.encode('{"format":1}')),
      ('Books/x/big.jpg', randomBytes(3, 100 * 1024)),
      ('Mekuru data/settings.mekuru', utf8.encode('{"version":1}')),
    ]);

    test('tells JSON from a zip without the entry', () async {
      final json = File(p.join(tmp.path, 'data.mekuru'))
        ..writeAsStringSync('{"version":1}');
      final notZip = await peekZip(json, 'manifest.json');
      expect(notZip.isZip, isFalse);
      expect(notZip.text, isNull);

      final zip = await archive();
      final missing = await peekZip(zip, 'other.json');
      expect(missing.isZip, isTrue);
      expect(missing.text, isNull);
      expect(missing.complete, isTrue);
      expect((await peekZip(zip, 'manifest.json')).text, '{"format":1}');
    });

    test('an entry that is not first is found through the directory', () async {
      final zip = await archive();
      expect(
        (await peekZip(zip, 'Mekuru data/settings.mekuru')).text,
        '{"version":1}',
      );
      expect(
        (await peekZip(zip, 'Books/x/big.jpg', maxBytes: 1024)).text,
        isNull,
      );
    });

    test('the manifest needs only the head of a truncated archive', () async {
      final zip = await archive();
      final bytes = zip.readAsBytesSync();
      final cut = File(p.join(tmp.path, 'cut.zip'))
        ..writeAsBytesSync(bytes.sublist(0, bytes.length ~/ 2));
      final peek = await peekZip(cut, 'manifest.json');
      expect(peek.isZip, isTrue);
      expect(peek.text, '{"format":1}');
      expect(peek.complete, isFalse);
      expect((await peekZip(cut, 'other.json')).text, isNull);
    });

    test('a manifest larger than the limit is not read', () async {
      final zip = await buildArchive(File(p.join(tmp.path, 'big.zip')), [
        ('manifest.json', utf8.encode('x' * 5000)),
      ]);
      expect(
        (await peekZip(zip, 'manifest.json', maxBytes: 1024)).text,
        isNull,
      );
    });

    test('reads the manifest of an archive another tool wrote', () async {
      final path = p.join(tmp.path, 'foreign.zip');
      final encoder = ZipFileEncoder()..create(path);
      encoder.addArchiveFile(
        ArchiveFile.string('manifest.json', '{"format":1}')
          ..compression = CompressionType.none,
      );
      await encoder.close();
      expect((await peekZip(File(path), 'manifest.json')).text, '{"format":1}');
    });

    test('the end record tells a finished archive from a cut one', () async {
      final bytes = (await archive()).readAsBytesSync();
      expect(zipHasEndRecord(bytes.sublist(bytes.length - 100)), isTrue);
      expect(zipHasEndRecord(bytes.sublist(0, bytes.length - 22)), isFalse);
      expect(zipHasEndRecord([0x50, 0x4B, 0x05]), isFalse);
    });
  });

  group('FullBackupZipWriter', () {
    final entries = [
      ('manifest.json', utf8.encode('{"format":1}')),
      ('Mekuru data/mekuru_db.sqlite', List.generate(300 * 1024, (i) => i % 7)),
      ('Books/メロス/本.epub', randomBytes(1, 120 * 1024)),
      ('Manga/漫画/001.jpg', randomBytes(2, 90 * 1024)),
      ('Mekuru data/unidic-lite/.install_complete', <int>[]),
    ];

    test('archive reads it back, names in order and bytes intact', () async {
      final zip = await buildArchive(File(p.join(tmp.path, 'w.zip')), entries);
      final read = readZip(zip);
      expect(read.keys.toList(), entries.map((e) => e.$1).toList());
      for (final (name, bytes) in entries) {
        expect(read[name], bytes, reason: name);
      }
      // Deflate paid off on the database; the stored page cost only block
      // headers.
      expect(zip.lengthSync(), lessThan(120 * 1024 + 90 * 1024 + 64 * 1024));
    });

    test('entries carry their modification time', () async {
      final zip = await buildArchive(File(p.join(tmp.path, 't.zip')), entries);
      final input = InputFileStream(zip.path);
      final first = ZipDecoder().decodeStream(input).first;
      input.closeSync();
      // Zip times are local wall-clock; `archive` hands the fields back
      // labelled UTC.
      final t = first.lastModDateTime;
      final local = DateTime(
        t.year,
        t.month,
        t.day,
        t.hour,
        t.minute,
        t.second,
      );
      final expected = DateTime.fromMillisecondsSinceEpoch(fixtureMtime);
      expect(local.difference(expected).inSeconds.abs(), lessThan(2));
      expect(zipDosTime(0), (1 << 21) | (1 << 16));
    });

    test('forced ZIP64 records read back the same', () async {
      final zip = await buildArchive(
        File(p.join(tmp.path, 'z64.zip')),
        entries,
        forceZip64: true,
      );
      final read = readZip(zip);
      for (final (name, bytes) in entries) {
        expect(read[name], bytes, reason: name);
      }
      final headers = readZipDirectory(zip.path);
      expect(headers.map((h) => h.filename), entries.map((e) => e.$1));
    });
  });

  group('extractZipEntry', () {
    final payload = randomBytes(5, 200 * 1024);

    Future<File> archive() => buildArchive(File(p.join(tmp.path, 'x.zip')), [
      ('manifest.json', utf8.encode('{"format":1}')),
      ('Manga/漫画/001.jpg', payload),
    ]);

    Future<void> extract(File zip, File target) async {
      final header = readZipDirectory(zip.path).last;
      final handle = await zip.open();
      try {
        await extractZipEntry(zip, handle, header, target);
      } finally {
        await handle.close();
      }
    }

    test('streams an entry out and checks it', () async {
      final target = File(p.join(tmp.path, 'out.jpg'));
      await extract(await archive(), target);
      expect(target.readAsBytesSync(), payload);
    });

    test('a flipped byte is a corrupt archive', () async {
      final zip = await archive();
      corruptEntry(zip, 'Manga/漫画/001.jpg');
      await expectLater(
        extract(zip, File(p.join(tmp.path, 'out.jpg'))),
        throwsA(isA<CorruptZipException>()),
      );
    });

    test('an archive without its end record has no directory', () async {
      final bytes = (await archive()).readAsBytesSync();
      final cut = File(p.join(tmp.path, 'cut.zip'))
        ..writeAsBytesSync(bytes.sublist(0, bytes.length - 22));
      expect(
        () => readZipDirectory(cut.path),
        throwsA(isA<CorruptZipException>()),
      );
    });
  });
}
