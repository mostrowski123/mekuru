import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;

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

/// Creates a fixed-layout (image-per-page) manga EPUB for testing.
///
/// Page `i` (0-based, spine order) is a PNG sized `(10 + i) x (100 + i)`, so
/// tests can tell which source image landed on which converted page purely by
/// its dimensions. Every XHTML doc contains `&nbsp;` to require the HTML5
/// entity mapping when parsed.
///
/// Returns the path to the written file; the caller owns cleanup of the
/// containing temp directory (the file's parent).
Future<String> createFixedLayoutMangaEpub({
  int pageCount = 5,
  List<String>? imageNames,
  bool svgWrapped = false,
  int textOnlyPages = 0,
  bool nestedImageDir = false,
  bool urlEncodedHrefs = false,
  bool coverPageReusesFirstImage = false,
}) async {
  final names = imageNames ?? [for (var i = 0; i < pageCount; i++) 'p$i.png'];
  final archive = Archive();

  void addEntry(String path, List<int> bytes) {
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  void addText(String path, String content) =>
      addEntry(path, utf8.encode(content));

  addText('META-INF/container.xml', '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''');

  final docDir = nestedImageDir ? 'text/' : '';
  String imageRef(String name) {
    final encoded = urlEncodedHrefs ? Uri.encodeComponent(name) : name;
    return nestedImageDir ? '../images/$encoded' : 'images/$encoded';
  }

  String pageDoc(String name) {
    final body = svgWrapped
        ? '<svg xmlns="http://www.w3.org/2000/svg" '
              'xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 10 10">'
              '<image xlink:href="${imageRef(name)}" width="10" height="10"/></svg>'
        : '<img src="${imageRef(name)}" alt=""/>';
    return '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>&nbsp;</title></head>
<body>$body</body>
</html>''';
  }

  final manifestItems = <String>[];
  final spineRefs = <String>[];

  if (coverPageReusesFirstImage) {
    addText('OEBPS/${docDir}cover.xhtml', pageDoc(names.first));
    manifestItems.add(
      '<item id="coverpage" href="${docDir}cover.xhtml" media-type="application/xhtml+xml"/>',
    );
    spineRefs.add('<itemref idref="coverpage"/>');
  }

  for (var i = 0; i < names.length; i++) {
    addEntry(
      'OEBPS/images/${names[i]}',
      img.encodePng(img.Image(width: 10 + i, height: 100 + i)),
    );
    addText('OEBPS/${docDir}page_$i.xhtml', pageDoc(names[i]));
    manifestItems
      ..add(
        '<item id="img$i" href="images/${names[i]}" media-type="image/png"/>',
      )
      ..add(
        '<item id="page$i" href="${docDir}page_$i.xhtml" media-type="application/xhtml+xml"/>',
      );
    spineRefs.add('<itemref idref="page$i"/>');
  }

  for (var i = 0; i < textOnlyPages; i++) {
    addText('OEBPS/text_$i.xhtml', '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>Text</title></head>
<body><p>あとがき&nbsp;$i</p></body>
</html>''');
    manifestItems.add(
      '<item id="txt$i" href="text_$i.xhtml" media-type="application/xhtml+xml"/>',
    );
    spineRefs.add('<itemref idref="txt$i"/>');
  }

  addText('OEBPS/content.opf', '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>漫画テスト</dc:title>
    <dc:language>ja</dc:language>
  </metadata>
  <manifest>
    ${manifestItems.join('\n    ')}
  </manifest>
  <spine page-progression-direction="rtl">
    ${spineRefs.join('\n    ')}
  </spine>
</package>''');

  final tempDir = await Directory.systemTemp.createTemp('epub_manga_test_');
  final epubPath = '${tempDir.path}/manga.epub';
  await File(epubPath).writeAsBytes(ZipEncoder().encode(archive));

  return epubPath;
}
