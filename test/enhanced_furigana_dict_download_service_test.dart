import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Tests the local-extraction side of the enhanced-furigana-dict downloader.
/// The HTTP and SHA-256 paths require network access and a real release
/// artifact, so they're covered by a manual smoke test on device rather
/// than by these unit tests.
///
/// Mirrors the private `_extractTarGz` logic in the service so we can
/// exercise it against synthetic archives.
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
  });
}

ArchiveFile _file(String name, List<int> bytes) =>
    ArchiveFile(name, bytes.length, bytes);

Uint8List _encodeTarGz(Archive archive) {
  final tarBytes = TarEncoder().encode(archive);
  final gzipped = GZipEncoder().encode(tarBytes);
  return Uint8List.fromList(gzipped);
}

/// Mirrors the service's private `_extractTarGz` so the same logic is
/// exercised under test.
void _extractTarGz(Uint8List archiveBytes, String outputDir) {
  final decompressed = GZipDecoder().decodeBytes(archiveBytes);
  final archive = TarDecoder().decodeBytes(decompressed);
  for (final entry in archive) {
    if (!entry.isFile) continue;
    final fileName = p.basename(entry.name);
    if (fileName.isEmpty || fileName.startsWith('.')) continue;
    final outputPath = p.join(outputDir, fileName);
    final file = File(outputPath);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(entry.content as List<int>);
  }
}
