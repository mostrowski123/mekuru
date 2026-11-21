import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/library/data/services/epub_furigana_export.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';

import '../../shared/io_recorder.dart';

/// An EPUB several chunks big: a chapter with ruby, plus incompressible
/// "images" both deflated and STORED, the two ways books carry them.
Uint8List _bigEpub(Random random) {
  Uint8List noise(int length) =>
      Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
  final archive = Archive()
    ..addFile(
      ArchiveFile.noCompress(
        'mimetype',
        20,
        utf8.encode('application/epub+zip'),
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'META-INF/container.xml',
        '<?xml version="1.0"?><container version="1.0" '
            'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
            '<rootfiles><rootfile full-path="OEBPS/content.opf" '
            'media-type="application/oebps-package+xml"/></rootfiles>'
            '</container>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/content.opf',
        '<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" '
            'version="3.0"><manifest><item id="c" href="c.xhtml" '
            'media-type="application/xhtml+xml"/></manifest>'
            '<spine><itemref idref="c"/></spine></package>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/c.xhtml',
        '<html xmlns="http://www.w3.org/1999/xhtml"><body>'
            '<p><ruby>既存<rt>きそん</rt></ruby></p></body></html>',
      ),
    )
    ..addFile(ArchiveFile.bytes('OEBPS/deflated.jpg', noise(3 * archiveChunk)))
    ..addFile(
      ArchiveFile.noCompress(
        'OEBPS/stored.jpg',
        3 * archiveChunk,
        noise(3 * archiveChunk),
      ),
    );
  return ZipEncoder().encodeBytes(archive);
}

void main() {
  late Directory dir;
  late String bookPath;
  late Uint8List book;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('furigana_streaming_');
    book = _bigEpub(Random(1));
    bookPath = '${dir.path}/book.epub';
    await File(bookPath).writeAsBytes(book);
  });

  tearDownAll(() => dir.delete(recursive: true));

  for (final mode in [FuriganaMode.book, FuriganaMode.hide]) {
    test('${mode.name} export streams file to file: no read or write is '
        'book-sized', () async {
      final outPath = '${dir.path}/${mode.name}.epub';
      final io = IoRecorder();

      final written = await IOOverrides.runWithIOOverrides(
        () => writeFuriganaEpub(bookPath, outPath, mode: mode),
        io,
      );

      expect(written, isTrue);
      expect(book.length, greaterThan(6 * archiveChunk));
      expect(io.largestRead, lessThanOrEqualTo(archiveChunk));
      expect(io.largestWrite, lessThanOrEqualTo(archiveChunk));

      final out = ZipDecoder().decodeBytes(File(outPath).readAsBytesSync());
      expect(out.files.first.name, 'mimetype');
      expect(out.files.first.compression, CompressionType.none);
      final source = ZipDecoder().decodeBytes(book);
      expect(
        [for (final f in out.files) (f.name, f.compression)],
        [for (final f in source.files) (f.name, f.compression)],
      );
      for (final name in ['OEBPS/deflated.jpg', 'OEBPS/stored.jpg']) {
        expect(out.findFile(name)!.content, source.findFile(name)!.content);
      }
      final chapter = utf8.decode(out.findFile('OEBPS/c.xhtml')!.content);
      expect(chapter.contains('<rt>'), mode == FuriganaMode.book);
    });
  }
}
