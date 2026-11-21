import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/data/services/manga_cbz_export.dart';
import 'package:path/path.dart' as p;

import '../../shared/io_recorder.dart';

/// "Export as CBZ" hands the share sheet the finished file's path, never its
/// bytes (share_plus sends paths for files that have one). What bounds the
/// volume it can export is then the build: it must stream page by page, or
/// a big volume would be held in memory whole.
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('cbz_streaming_'));
  tearDown(() => dir.deleteSync(recursive: true));

  test(
    'the CBZ streams file to file: no read or write is volume-sized',
    () async {
      final random = Random(1);
      final imageDir = Directory(p.join(dir.path, 'images'))..createSync();
      final pages = <MokuroPage>[];
      final images = <String, Uint8List>{};
      for (var i = 0; i < 3; i++) {
        final name = 'page_$i.jpg';
        final bytes = Uint8List.fromList(
          List.generate(3 * archiveChunk, (_) => random.nextInt(256)),
        );
        File(p.join(imageDir.path, name)).writeAsBytesSync(bytes);
        images[name] = bytes;
        pages.add(
          MokuroPage(
            pageIndex: i,
            imageFileName: name,
            imgWidth: 800,
            imgHeight: 1200,
            blocks: const [],
          ),
        );
      }
      File(p.join(dir.path, mangaPagesCacheFileName)).writeAsStringSync(
        jsonEncode(
          MokuroBook(
            title: '巻',
            imageDirPath: imageDir.path,
            ocrSource: 'mokuro',
            ocrCompleted: false,
            pages: pages,
          ).toJson(),
        ),
      );
      final outPath = p.join(dir.path, 'out.cbz');
      final io = IoRecorder();

      final written = await IOOverrides.runWithIOOverrides(
        () => writeCbz(dir.path, outPath, title: '巻', rtl: true),
        io,
      );

      expect(written, 3);
      expect(File(outPath).lengthSync(), greaterThan(9 * archiveChunk));
      // The pages went through the recorder: these bounds measured something.
      expect(io.largestRead, inInclusiveRange(1, archiveChunk));
      expect(io.largestWrite, inInclusiveRange(1, archiveChunk));

      final cbz = ZipDecoder().decodeBytes(File(outPath).readAsBytesSync());
      final stored = [
        for (final f in cbz.files)
          if (f.name.endsWith('.jpg')) f,
      ];
      expect(stored, hasLength(3));
      for (final (i, file) in stored.indexed) {
        expect(file.compression, CompressionType.none);
        expect(file.content, images['page_$i.jpg']);
      }
    },
  );
}
