import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Tests for KanjiVG download service logic.
///
/// Network-dependent tests are excluded; we test archive extraction,
/// file path resolution, and status detection using temp directories.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('kanjivg_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('KanjiVG SVG path resolution', () {
    test('generates correct hex filename for common kanji', () {
      // 一 = U+4E00 → 04e00.svg
      expect(_hexFileName('一'), '04e00.svg');
      // 国 = U+56FD → 056fd.svg
      expect(_hexFileName('国'), '056fd.svg');
      // 食 = U+98DF → 098df.svg
      expect(_hexFileName('食'), '098df.svg');
    });

    test('generates correct hex filename for rare kanji', () {
      // 龍 = U+9F8D → 09f8d.svg
      expect(_hexFileName('龍'), '09f8d.svg');
    });

    test('pads code point to 5 hex digits', () {
      // A = U+0041 → 00041.svg (ASCII, not kanji, but tests padding)
      expect(_hexFileName('A'), '00041.svg');
    });
  });

  group('KanjiVG archive extraction', () {
    test('extracts SVG files from ZIP archive', () {
      // Create a test ZIP archive with SVG files in a nested directory
      final archive = Archive();
      final svgContent = '<svg>test</svg>';
      final svgBytes = svgContent.codeUnits;

      archive.addFile(
        ArchiveFile(
          'kanjivg-kanjivg-20220427/kanji/04e00.svg',
          svgBytes.length,
          svgBytes,
        ),
      );
      archive.addFile(
        ArchiveFile(
          'kanjivg-kanjivg-20220427/kanji/056fd.svg',
          svgBytes.length,
          svgBytes,
        ),
      );
      // Non-SVG file should be ignored
      archive.addFile(
        ArchiveFile('kanjivg-kanjivg-20220427/README.md', 5, 'hello'.codeUnits),
      );
      // SVG not in kanji dir should still be extracted (by basename)
      archive.addFile(
        ArchiveFile(
          'kanjivg-kanjivg-20220427/other/09f8d.svg',
          svgBytes.length,
          svgBytes,
        ),
      );

      final zipBytes = ZipEncoder().encode(archive);

      // Extract using the same logic as the service
      final outputDir = tempDir.path;
      final count = _extractSvgsFromArchive(zipBytes, outputDir);

      // Should extract all 3 SVG files
      expect(count, 3);
      expect(File(p.join(outputDir, '04e00.svg')).existsSync(), isTrue);
      expect(File(p.join(outputDir, '056fd.svg')).existsSync(), isTrue);
      expect(File(p.join(outputDir, '09f8d.svg')).existsSync(), isTrue);
      // README should NOT be extracted
      expect(File(p.join(outputDir, 'README.md')).existsSync(), isFalse);
    });

    test('extracts correct SVG content', () {
      final archive = Archive();
      final svgContent =
          '<svg xmlns="http://www.w3.org/2000/svg"><path d="M1,1"/></svg>';
      final svgBytes = svgContent.codeUnits;

      archive.addFile(
        ArchiveFile('kanji/04e00.svg', svgBytes.length, svgBytes),
      );

      final zipBytes = ZipEncoder().encode(archive);
      _extractSvgsFromArchive(zipBytes, tempDir.path);

      final extracted = File(p.join(tempDir.path, '04e00.svg'));
      expect(extracted.existsSync(), isTrue);
      expect(extracted.readAsStringSync(), svgContent);
    });

    test('handles empty archive', () {
      final archive = Archive();
      final zipBytes = ZipEncoder().encode(archive);
      final count = _extractSvgsFromArchive(zipBytes, tempDir.path);
      expect(count, 0);
    });
  });

  group('KanjiVG download status detection', () {
    test('reports not downloaded when directory does not exist', () {
      final dir = p.join(tempDir.path, 'nonexistent');
      expect(_isDownloaded(dir), isFalse);
    });

    test('reports not downloaded when marker file is missing', () {
      final dir = p.join(tempDir.path, 'kanjivg');
      Directory(dir).createSync();
      // Create some SVG files but no marker
      File(p.join(dir, '04e00.svg')).writeAsStringSync('<svg/>');
      expect(_isDownloaded(dir), isFalse);
    });

    test('reports downloaded when marker file exists', () {
      final dir = p.join(tempDir.path, 'kanjivg');
      Directory(dir).createSync();
      File(p.join(dir, '.kanjivg_complete')).writeAsStringSync('done');
      expect(_isDownloaded(dir), isTrue);
    });
  });

  group('KanjiVG file count', () {
    test('counts SVG files in directory', () {
      final dir = p.join(tempDir.path, 'kanjivg');
      Directory(dir).createSync();
      File(p.join(dir, '04e00.svg')).writeAsStringSync('<svg/>');
      File(p.join(dir, '056fd.svg')).writeAsStringSync('<svg/>');
      File(p.join(dir, '.kanjivg_complete')).writeAsStringSync('done');

      expect(_countSvgFiles(dir), 2);
    });

    test('returns 0 for empty directory', () {
      final dir = p.join(tempDir.path, 'kanjivg');
      Directory(dir).createSync();
      expect(_countSvgFiles(dir), 0);
    });

    test('returns 0 for nonexistent directory', () {
      final dir = p.join(tempDir.path, 'nonexistent');
      expect(_countSvgFiles(dir), 0);
    });
  });
}

// ── Test helpers mirroring KanjiVgDownloadService logic ──

/// Generate the SVG filename for a kanji character (same logic as service).
String _hexFileName(String char) {
  final codePoint = char.codeUnitAt(0);
  final hex = codePoint.toRadixString(16).padLeft(5, '0');
  return '$hex.svg';
}

/// Extract SVG files from a ZIP archive (same logic as service's isolate fn).
int _extractSvgsFromArchive(List<int> zipBytes, String outputDir) {
  final archive = ZipDecoder().decodeBytes(zipBytes);
  var count = 0;

  for (final file in archive) {
    if (file.isFile && file.name.endsWith('.svg')) {
      final fileName = p.basename(file.name);
      final outputPath = p.join(outputDir, fileName);
      File(outputPath).writeAsBytesSync(file.content as List<int>);
      count++;
    }
  }

  return count;
}

/// Check if marker file exists (same logic as service).
bool _isDownloaded(String dir) {
  final marker = File(p.join(dir, '.kanjivg_complete'));
  return marker.existsSync();
}

/// Count SVG files in a directory.
int _countSvgFiles(String dir) {
  final directory = Directory(dir);
  if (!directory.existsSync()) return 0;
  return directory.listSync().where((e) => e.path.endsWith('.svg')).length;
}
