import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/library/data/services/epub_parser.dart';

/// Creates a minimal valid EPUB zip file for testing.
Future<String> createTestEpub({
  String title = 'テスト本',
  String? author,
  bool includeCover = true,
  bool includeContainerXml = true,
  String? customOpfContent,
}) async {
  final archive = Archive();

  // META-INF/container.xml
  if (includeContainerXml) {
    final containerXml = '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''';
    final containerBytes = utf8.encode(containerXml);
    archive.addFile(
      ArchiveFile(
        'META-INF/container.xml',
        containerBytes.length,
        containerBytes,
      ),
    );
  }

  // OEBPS/content.opf
  final opfContent =
      customOpfContent ??
      '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>$title</dc:title>
    ${author != null ? '<dc:creator>$author</dc:creator>' : ''}
    <meta name="cover" content="cover-img"/>
  </metadata>
  <manifest>
    ${includeCover ? '<item id="cover-img" href="images/cover.jpg" media-type="image/jpeg"/>' : ''}
    <item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="chapter1"/>
  </spine>
</package>''';
  final opfBytes = utf8.encode(opfContent);
  archive.addFile(ArchiveFile('OEBPS/content.opf', opfBytes.length, opfBytes));

  // Cover image (tiny 1x1 JPEG placeholder)
  if (includeCover) {
    // Minimal valid JPEG (1x1 pixel)
    final jpegBytes = [
      0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, //
      0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xD9,
    ];
    archive.addFile(
      ArchiveFile('OEBPS/images/cover.jpg', jpegBytes.length, jpegBytes),
    );
  }

  // Chapter content
  final chapterContent = utf8.encode('''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>Chapter 1</title></head>
<body><p>これはテストです。</p></body>
</html>''');
  archive.addFile(
    ArchiveFile('OEBPS/chapter1.xhtml', chapterContent.length, chapterContent),
  );

  // Write to temp file
  final tempDir = await Directory.systemTemp.createTemp('epub_test_');
  final epubPath = '${tempDir.path}/test.epub';
  await File(epubPath).writeAsBytes(ZipEncoder().encode(archive));

  return epubPath;
}

void main() {
  final tempDirs = <String>[];

  tearDown(() async {
    for (final path in tempDirs) {
      try {
        final dir = Directory(path).parent;
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      } catch (_) {
        // Windows may lock temp files — they'll be cleaned up by OS
      }
    }
    tempDirs.clear();
  });

  group('EpubParser — parseMetadataOnly', () {
    test('extracts title from dc:title', () async {
      final epubPath = await createTestEpub(title: '吾輩は猫である');
      tempDirs.add(epubPath);

      final metadata = await EpubParser.parseMetadataOnly(epubPath);
      expect(metadata.title, '吾輩は猫である');
    });

    test('extracts author from dc:creator', () async {
      final epubPath = await createTestEpub(title: '坊っちゃん', author: '夏目漱石');
      tempDirs.add(epubPath);

      final metadata = await EpubParser.parseMetadataOnly(epubPath);
      expect(metadata.author, '夏目漱石');
    });

    test('returns null author when not present', () async {
      final epubPath = await createTestEpub();
      tempDirs.add(epubPath);

      final metadata = await EpubParser.parseMetadataOnly(epubPath);
      expect(metadata.author, isNull);
    });

    test('finds cover image path via meta name="cover"', () async {
      final epubPath = await createTestEpub(includeCover: true);
      tempDirs.add(epubPath);

      final metadata = await EpubParser.parseMetadataOnly(epubPath);
      expect(metadata.coverImageRelativePath, isNotNull);
      expect(metadata.coverImageRelativePath, contains('cover.jpg'));
    });

    test('returns null coverImageRelativePath when no cover', () async {
      final epubPath = await createTestEpub(includeCover: false);
      tempDirs.add(epubPath);

      final metadata = await EpubParser.parseMetadataOnly(epubPath);
      expect(metadata.coverImageRelativePath, isNull);
    });

    test('returns Unknown Title when container.xml is missing', () async {
      final epubPath = await createTestEpub(includeContainerXml: false);
      tempDirs.add(epubPath);

      final metadata = await EpubParser.parseMetadataOnly(epubPath);
      expect(metadata.title, 'Unknown Title');
    });

    test('throws FileSystemException for non-existent file', () async {
      expect(
        () => EpubParser.parseMetadataOnly('/nonexistent/book.epub'),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  group('EpubParser — parseEpub (full extraction)', () {
    test('extracts all files and returns metadata', () async {
      final epubPath = await createTestEpub(title: '走れメロス', author: '太宰治');
      tempDirs.add(epubPath);

      final extractDir = await Directory.systemTemp.createTemp('epub_extract_');
      tempDirs.add(extractDir.path);

      final metadata = await EpubParser.parseEpub(epubPath, extractDir.path);

      expect(metadata.title, '走れメロス');
      expect(metadata.author, '太宰治');

      // Verify files were extracted
      final containerFile = File('${extractDir.path}/META-INF/container.xml');
      expect(await containerFile.exists(), isTrue);

      final opfFile = File('${extractDir.path}/OEBPS/content.opf');
      expect(await opfFile.exists(), isTrue);

      final chapterFile = File('${extractDir.path}/OEBPS/chapter1.xhtml');
      expect(await chapterFile.exists(), isTrue);
    });

    test('extracts cover image file', () async {
      final epubPath = await createTestEpub(includeCover: true);
      tempDirs.add(epubPath);

      final extractDir = await Directory.systemTemp.createTemp(
        'epub_extract_cover_',
      );
      tempDirs.add(extractDir.path);

      final metadata = await EpubParser.parseEpub(epubPath, extractDir.path);

      expect(metadata.coverImageRelativePath, isNotNull);
      final coverFile = File(
        '${extractDir.path}/${metadata.coverImageRelativePath}',
      );
      expect(await coverFile.exists(), isTrue);
    });
  });

  group('EpubParser — EPUB 3 cover-image property', () {
    test('finds cover via properties="cover-image" (EPUB 3)', () async {
      final opfContent = '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>EPUB3 Book</dc:title>
  </metadata>
  <manifest>
    <item id="cover" href="images/cover.png" media-type="image/png" properties="cover-image"/>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
  </manifest>
</package>''';

      final epubPath = await createTestEpub(
        customOpfContent: opfContent,
        includeCover: false,
      );
      tempDirs.add(epubPath);

      final metadata = await EpubParser.parseMetadataOnly(epubPath);
      expect(metadata.coverImageRelativePath, contains('cover.png'));
    });
  });

  group('EpubParser — fallback cover detection', () {
    test(
      'finds cover via item id containing "cover" with image media type',
      () async {
        final opfContent = '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Fallback Cover Book</dc:title>
  </metadata>
  <manifest>
    <item id="cover-image" href="cover.jpg" media-type="image/jpeg"/>
    <item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
</package>''';

        final epubPath = await createTestEpub(
          customOpfContent: opfContent,
          includeCover: false,
        );
        tempDirs.add(epubPath);

        final metadata = await EpubParser.parseMetadataOnly(epubPath);
        expect(metadata.coverImageRelativePath, contains('cover.jpg'));
      },
    );
  });
}
