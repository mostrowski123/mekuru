import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/data/services/cbz_parser.dart';
import 'package:path/path.dart' as p;

/// Thrown when a manga book has no pages that can be exported.
class EmptyMangaExportException implements Exception {
  const EmptyMangaExportException();
}

/// Thrown when a manga book's images live behind SAF and cannot be exported.
// ponytail: SAF-backed export would need BackgroundIsolateBinaryMessenger +
// AndroidSafService.readBytesFromTreePath; mokuro folder importers already
// own their images on disk, so refusing is fine until someone asks.
class SafMangaExportUnsupportedException implements Exception {
  const SafMangaExportUnsupportedException();
}

/// Writes the manga book at [cacheDirPath] into a stored (uncompressed) CBZ
/// at [outPath]. Returns the number of pages written.
///
/// Pages are named by zero-padded cache order (`0001.png`, `0002.jpg`, …) so
/// any natural-sorting reader — mokuro included — sees them in book order.
/// Entries stream file-to-file (stored, no deflate), so peak memory stays at
/// about one I/O buffer regardless of volume size.
Future<int> writeCbz(String cacheDirPath, String outPath) async {
  final cacheFile = File(p.join(cacheDirPath, mangaPagesCacheFileName));
  final book = MokuroBook.fromJson(
    jsonDecode(await cacheFile.readAsString()) as Map<String, dynamic>,
  );
  if (book.safTreeUri != null) {
    throw const SafMangaExportUnsupportedException();
  }

  var written = 0;
  final mokuroPages = <Map<String, dynamic>>[];
  final encoder = ZipFileEncoder()..create(outPath);
  try {
    for (final page in book.pages) {
      final imagePath = p.join(book.imageDirPath, page.imageFileName);
      if (!await File(imagePath).exists()) continue;
      written++;
      final name = CbzParser.pageFileName(written, page.imageFileName);
      mokuroPages.add({
        'img_path': name,
        'img_width': page.imgWidth,
        'img_height': page.imgHeight,
        'blocks': [for (final block in page.blocks) block.toOcrJson()],
      });
      // Stored, not deflated: pages are already-compressed JPEG/PNG, and the
      // stored path streams straight to the output file. add() closes the
      // InputFileStream itself.
      encoder.addArchiveFile(
        ArchiveFile.stream(name, InputFileStream(imagePath))
          ..compression = CompressionType.none,
      );
    }
    // Embed the OCR data as a standard .mokuro entry so importing this CBZ
    // (on any device, or after a round-trip through a Komga/Kavita server)
    // restores tap-to-lookup without re-running OCR. Books with no OCR data
    // export images-only, as before.
    if (book.pages.any((page) => page.blocks.isNotEmpty)) {
      final mokuroJson = jsonEncode({
        'version': '0.2.1',
        'title': book.title,
        'volume': book.title,
        'pages': mokuroPages,
      });
      encoder.addArchiveFile(
        ArchiveFile.string(
          '${p.basenameWithoutExtension(outPath)}.mokuro',
          mokuroJson,
        ),
      );
    }
    await encoder.close();
    if (written == 0) throw const EmptyMangaExportException();
  } catch (_) {
    try {
      await encoder.close();
    } catch (_) {}
    try {
      await File(outPath).delete();
    } catch (_) {}
    rethrow;
  }
  return written;
}
