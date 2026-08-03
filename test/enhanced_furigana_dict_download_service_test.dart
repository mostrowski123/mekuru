import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/settings/data/services/enhanced_furigana_dict_download_service.dart';
import 'package:path/path.dart' as p;

/// Tests the verify-and-extract side of the enhanced-furigana-dict
/// downloader through the service's real isolate entry point, using
/// synthetic archives. The HTTP path is covered by
/// `test/core/download_to_file_test.dart`.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('unidic_lite_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('unidic-lite tar.gz extraction', () {
    test('flattens nested tar entries by basename into output dir', () {
      final archive = Archive()
        ..addFile(_file('unidic-lite-2.1.2/sys.dic', [1, 2, 3]))
        ..addFile(_file('unidic-lite-2.1.2/matrix.bin', [4, 5, 6]))
        ..addFile(_file('unidic-lite-2.1.2/dicrc', 'foo'.codeUnits));

      _extractTarGz(_encodeTarGz(archive), tempDir.path);

      expect(File(p.join(tempDir.path, 'sys.dic')).existsSync(), isTrue);
      expect(File(p.join(tempDir.path, 'matrix.bin')).existsSync(), isTrue);
      expect(File(p.join(tempDir.path, 'dicrc')).readAsStringSync(), 'foo');
    });

    test('skips hidden dotfiles and directories', () {
      final archive = Archive()
        ..addFile(_file('unidic-lite-2.1.2/.DS_Store', [0]))
        ..addFile(_file('unidic-lite-2.1.2/dicrc', 'foo'.codeUnits));

      _extractTarGz(_encodeTarGz(archive), tempDir.path);

      expect(File(p.join(tempDir.path, '.DS_Store')).existsSync(), isFalse);
      expect(File(p.join(tempDir.path, 'dicrc')).existsSync(), isTrue);
    });

    test('handles empty archive without error', () {
      _extractTarGz(_encodeTarGz(Archive()), tempDir.path);
      expect(Directory(tempDir.path).listSync(), isEmpty);
    });

    test('streams entries larger than the extraction buffer intact', () {
      // 3 MB exceeds the 1 MB chunk size used by the streaming extraction
      // path, so this exercises multi-chunk writes end to end.
      final bigContent = Uint8List(3 * 1024 * 1024);
      for (var i = 0; i < bigContent.length; i++) {
        bigContent[i] = i & 0xff;
      }
      final archive = Archive()
        ..addFile(_file('unidic-lite-2.1.2/sys.dic', bigContent))
        ..addFile(_file('unidic-lite-2.1.2/dicrc', 'foo'.codeUnits));

      _extractTarGz(_encodeTarGz(archive), tempDir.path);

      final extracted = File(p.join(tempDir.path, 'sys.dic')).readAsBytesSync();
      expect(extracted.length, bigContent.length);
      expect(sha256.convert(extracted), sha256.convert(bigContent));
      expect(File(p.join(tempDir.path, 'dicrc')).readAsStringSync(), 'foo');
    });

    test('rejects an archive whose hash does not match', () {
      final archive = Archive()
        ..addFile(_file('unidic-lite-2.1.2/dicrc', 'foo'.codeUnits));

      expect(
        () => _verifyAndExtract(
          _encodeTarGz(archive),
          tempDir.path,
          expectedSha256: 'not-the-real-hash',
        ),
        throwsFormatException,
      );
      expect(Directory(tempDir.path).listSync(), isEmpty);
    });
  });
}

ArchiveFile _file(String name, List<int> bytes) =>
    ArchiveFile(name, bytes.length, bytes);

Uint8List _encodeTarGz(Archive archive) {
  final tarBytes = TarEncoder().encode(archive);
  final gzipped = GZipEncoder().encode(tarBytes);
  return Uint8List.fromList(gzipped);
}

/// Write [archiveBytes] to disk and run the service's real isolate entry
/// point with a matching SHA-256, so extraction is exercised end to end.
void _extractTarGz(Uint8List archiveBytes, String outputDir) {
  _verifyAndExtract(
    archiveBytes,
    outputDir,
    expectedSha256: sha256.convert(archiveBytes).toString(),
  );
}

void _verifyAndExtract(
  Uint8List archiveBytes,
  String outputDir, {
  required String expectedSha256,
}) {
  final archiveDir = Directory.systemTemp.createTempSync('unidic_archive_');
  addTearDown(() => archiveDir.deleteSync(recursive: true));
  final archivePath = p.join(archiveDir.path, 'archive.tar.gz');
  File(archivePath).writeAsBytesSync(archiveBytes);

  EnhancedFuriganaDictDownloadService.verifyAndExtractTarGz((
    archivePath: archivePath,
    outputDir: outputDir,
    expectedSha256: expectedSha256,
  ));

  expect(
    archiveDir.listSync().map((entity) => p.basename(entity.path)).toList(),
    ['archive.tar.gz'],
    reason: 'extraction must not leave temp files next to the archive',
  );
}
