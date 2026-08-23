import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

/// Minimal valid JPEG (1x1 pixel) used as the fixture cover image.
const testCoverJpegBytes = [
  0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, //
  0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xD9,
];

/// Hand-crafted corrupt zip: a CDFH that claims a 255-byte filename, followed
/// by an EOCD that points back to byte 0. The decoder reads the CDFH header,
/// then tries to read the filename, runs past EOF, and throws — the same
/// RangeError path that crashed in production.
const corruptZipBytes = [
  // Central Directory File Header (46 bytes)
  0x50, 0x4B, 0x01, 0x02, // signature
  0x1F, 0x00, 0x0A, 0x00, // versions
  0x00, 0x00, 0x00, 0x00, // flags, compression
  0x00, 0x00, 0x00, 0x00, // mod time/date
  0x00, 0x00, 0x00, 0x00, // crc
  0x00, 0x00, 0x00, 0x00, // compressed size
  0x00, 0x00, 0x00, 0x00, // uncompressed size
  0xFF, 0x00, // filename length = 255 (no bytes follow)
  0x00, 0x00, // extra length
  0x00, 0x00, // comment length
  0x00, 0x00, // disk number
  0x00, 0x00, // internal attrs
  0x00, 0x00, 0x00, 0x00, // external attrs
  0x00, 0x00, 0x00, 0x00, // local header offset
  // End of Central Directory Record (22 bytes)
  0x50, 0x4B, 0x05, 0x06, // signature
  0x00, 0x00, 0x00, 0x00, // disk numbers
  0x01, 0x00, 0x01, 0x00, // entries
  0x2E, 0x00, 0x00, 0x00, // CD size = 46
  0x00, 0x00, 0x00, 0x00, // CD offset = 0
  0x00, 0x00, // comment length
];

/// Creates a minimal valid EPUB zip file for testing.
///
/// Returns the path to the written file; the caller owns cleanup of the
/// containing temp directory (the file's parent).
Future<String> createTestEpub({
  String title = 'テスト本',
  String? author,
  String? language,
  String? pageProgressionDirection,
  String? primaryWritingMode,
  bool includeCover = true,
  bool includeContainerXml = true,
  String? customOpfContent,
  String? stylesheetContent,
  String? chapterBodyStyle,
  String fileName = 'test.epub',
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
    ${language != null ? '<dc:language>$language</dc:language>' : ''}
    <meta name="cover" content="cover-img"/>
    ${primaryWritingMode != null ? '<meta name="primary-writing-mode" content="$primaryWritingMode"/>' : ''}
  </metadata>
  <manifest>
    ${includeCover ? '<item id="cover-img" href="images/cover.jpg" media-type="image/jpeg"/>' : ''}
    ${stylesheetContent != null ? '<item id="css-main" href="styles/main.css" media-type="text/css"/>' : ''}
    <item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine${pageProgressionDirection != null ? ' page-progression-direction="$pageProgressionDirection"' : ''}>
    <itemref idref="chapter1"/>
  </spine>
</package>''';
  final opfBytes = utf8.encode(opfContent);
  archive.addFile(ArchiveFile('OEBPS/content.opf', opfBytes.length, opfBytes));

  // Cover image (tiny 1x1 JPEG placeholder)
  if (includeCover) {
    archive.addFile(
      ArchiveFile(
        'OEBPS/images/cover.jpg',
        testCoverJpegBytes.length,
        testCoverJpegBytes,
      ),
    );
  }

  // Stylesheet
  if (stylesheetContent != null) {
    final cssBytes = utf8.encode(stylesheetContent);
    archive.addFile(
      ArchiveFile('OEBPS/styles/main.css', cssBytes.length, cssBytes),
    );
  }

  // Chapter content
  final bodyTag = chapterBodyStyle != null
      ? '<body style="$chapterBodyStyle">'
      : '<body>';
  final chapterContent = utf8.encode('''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>Chapter 1</title></head>
$bodyTag<p>これはテストです。</p></body>
</html>''');
  archive.addFile(
    ArchiveFile('OEBPS/chapter1.xhtml', chapterContent.length, chapterContent),
  );

  // Write to temp file
  final tempDir = await Directory.systemTemp.createTemp('epub_test_');
  final epubPath = '${tempDir.path}/$fileName';
  await File(epubPath).writeAsBytes(ZipEncoder().encode(archive));

  return epubPath;
}
