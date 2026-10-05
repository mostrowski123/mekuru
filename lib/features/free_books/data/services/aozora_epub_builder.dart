// Pure Dart (no Flutter UI imports): runs inside Isolate.run and in tests.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:charset/charset.dart';
import 'package:mekuru/core/utils/xhtml.dart';
import 'package:mekuru/features/free_books/data/models/aozora_work.dart';
import 'package:mekuru/features/manga/data/services/cbz_parser.dart';
import 'package:mime/mime.dart';
import 'package:xml/xml.dart';

/// Decodes an Aozora XHTML file: Shift_JIS unless its XML declaration says
/// UTF-8.
String decodeAozoraXhtml(List<int> bytes) {
  final head = String.fromCharCodes(bytes.take(200)).toLowerCase();
  return head.contains('utf-8')
      ? utf8.decode(bytes, allowMalformed: true)
      : const ShiftJISDecoder(allowMalformed: true).convert(bytes);
}

final _imageSrc = RegExp(r'<img\b[^>]*?\bsrc="([^"]+)"');

/// The `src` of every image in [xhtml] (gaiji glyphs and illustrations), as
/// written, so the downloader can fetch them before [buildAozoraEpub].
List<String> aozoraImageSources(String xhtml) =>
    {for (final match in _imageSrc.allMatches(xhtml)) match.group(1)!}.toList();

/// A chapter longer than this (serialized) is cut at the next paragraph:
/// epub.js lays out one spine item at a time, and heading-less novels arrive
/// as a single file.
const _maxChapterChars = 150000;

/// Notes that stand for a page break in Aozora's transcription rules.
const _breakNotes = ['改ページ', '改丁', '改段', '改見開き'];

/// Layout-only notes with nothing to say to a reader.
const _droppedNotes = ['ページの左右中央'];

/// Block elements that end the current line instead of joining it.
const _blockElements = {
  'div',
  'p',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'table',
  'ul',
  'ol',
  'center',
  'hr',
};

typedef _Doc = ({String id, String label, String body});

/// Builds a vertical EPUB 3 from one Aozora Bunko XHTML file.
///
/// [images] maps an `<img src>` exactly as written in [xhtml] (see
/// [aozoraImageSources]) to its bytes; an image without bytes falls back to
/// its alt text. The output is deterministic — the same input gives the same
/// files — because restoring a light backup matches books by a hash of
/// their extracted contents.
Uint8List buildAozoraEpub({
  required String xhtml,
  required AozoraWork work,
  Map<String, Uint8List> images = const {},
}) {
  final body = parseXhtml(xhtml)?.findAllElements('body').firstOrNull;
  if (body == null) {
    throw const FormatException('Aozora XHTML is not well-formed');
  }
  // Aozora's sections are all direct children of <body>.
  final sections = {
    for (final div in body.childElements) ?div.getAttribute('class'): div,
  };
  final mainText = sections['main_text'];
  if (mainText == null) {
    throw const FormatException('Aozora XHTML has no main text');
  }

  final cleaner = _Cleaner(images);
  final title = work.displayTitle;
  final titlePage = [
    for (final element
        in sections['metadata']?.childElements ?? const <XmlElement>[])
      if (element.name.local != 'br') cleaner.clean(element).toXmlString(),
  ].join('\n');
  final colophon = [
    for (final name in ['bibliographical_information', 'notation_notes'])
      if (sections[name] case final div?)
        for (final block in _blocks(div.children, cleaner))
          if (block is XmlElement && block.name.local != 'hr')
            block.toXmlString(),
  ].join('\n');
  final docs = <_Doc>[
    (id: 'title', label: title, body: titlePage),
    for (final (i, chapter) in _chapters(
      _blocks(mainText.children, cleaner),
    ).indexed)
      (
        id: 'c${(i + 1).toString().padLeft(4, '0')}',
        label: chapter.label ?? (i == 0 ? title : ''),
        body: chapter.body,
      ),
    (id: 'colophon', label: '奥付', body: colophon),
  ];

  final archive = Archive();
  void add(String name, String text) =>
      archive.addFile(ArchiveFile.bytes(name, utf8.encode(text)));
  archive.addFile(
    ArchiveFile.noCompress(
      'mimetype',
      _mimetype.length,
      utf8.encode(_mimetype),
    ),
  );
  add('META-INF/container.xml', _containerXml);
  add('OEBPS/style.css', _styleCss);
  add('OEBPS/content.opf', _opf(work, docs, cleaner.imageNames.values));
  add('OEBPS/nav.xhtml', _nav(title, docs));
  for (final doc in docs) {
    add(
      'OEBPS/text/${doc.id}.xhtml',
      _xhtml(
        title: doc.label,
        stylesheet: true,
        body: '<div class="main_text">\n${doc.body}\n</div>',
      ),
    );
  }
  for (final MapEntry(key: src, value: name) in cleaner.imageNames.entries) {
    archive.addFile(ArchiveFile.bytes('OEBPS/images/$name', images[src]!));
  }
  return ZipEncoder().encodeBytes(archive);
}

const _mimetype = 'application/epub+zip';

/// Rewrites Aozora markup into canonical EPUB 3.
class _Cleaner {
  _Cleaner(this.images);

  final Map<String, Uint8List> images;

  /// `src` as written → file name under `OEBPS/images/`, in first-use order.
  final imageNames = <String, String>{};

  XmlNode clean(XmlNode node) {
    if (node is! XmlElement) return node.copy();
    final name = node.name.local;
    if (name == 'img') return _image(node);
    if (name == 'ruby') {
      // Canonical EPUB 3 ruby: the base text directly in <ruby>, no <rb>,
      // no <rp> fallback brackets.
      return XmlElement(XmlName('ruby'), const [], [
        for (final child in node.children)
          if (child is XmlElement && child.name.local == 'rb')
            ...child.children.map(clean)
          else if (child is! XmlElement || child.name.local != 'rp')
            clean(child),
      ]);
    }
    // Same-line headings (dogyo-*) sit inside a line of text.
    final tag = _isInlineHeading(node) ? 'span' : name;
    return XmlElement(XmlName(tag), _attributes(node), [
      for (final child in node.children)
        if (child is! XmlElement || child.name.local != 'script') clean(child),
    ]);
  }

  XmlNode _image(XmlElement node) {
    final src = node.getAttribute('src') ?? '';
    if (!images.containsKey(src)) {
      return XmlText(node.getAttribute('alt') ?? '※');
    }
    final name = imageNames.putIfAbsent(
      src,
      () => CbzParser.pageFileName(imageNames.length + 1, src),
    );
    return XmlElement(XmlName('img'), [
      XmlAttribute(XmlName('src'), '../images/$name'),
      XmlAttribute(XmlName('alt'), node.getAttribute('alt') ?? ''),
      if (node.getAttribute('class') case final cls?)
        XmlAttribute(XmlName('class'), cls),
    ]);
  }
}

bool _isInlineHeading(XmlElement element) =>
    (element.getAttribute('class') ?? '').startsWith('dogyo-');

/// Copies attributes, turning physical left/right margins into logical ones
/// so indents (jisage) and bottom alignment (chitsuki) work in vertical text.
List<XmlAttribute> _attributes(XmlElement element) => [
  for (final attribute in element.attributes)
    if (attribute.name.prefix == null && attribute.name.local != 'xmlns')
      XmlAttribute(
        XmlName(attribute.name.local),
        attribute.name.local == 'style'
            ? attribute.value
                  .replaceAll('margin-left', 'margin-inline-start')
                  .replaceAll('margin-right', 'margin-inline-end')
            : attribute.value,
      ),
];

/// A page break taken from an Aozora note.
class _Break extends XmlComment {
  _Break() : super('break');
}

String? _noteText(XmlElement element) =>
    element.name.local == 'span' && element.getAttribute('class') == 'notes'
    ? element.innerText
    : null;

/// Turns Aozora's `<br />`-separated lines into paragraphs (keeping tap
/// context and reading positions paragraph-sized) and keeps block elements,
/// whose own lines become paragraphs too.
List<XmlNode> _blocks(Iterable<XmlNode> children, _Cleaner cleaner) {
  final out = <XmlNode>[];
  var line = <XmlNode>[];
  bool lineIsBlank() =>
      line.every((n) => n is XmlText && n.value.trim().isEmpty);
  void endLine({required bool keepBlank}) {
    if (lineIsBlank()) {
      if (keepBlank) {
        out.add(
          XmlElement(XmlName('p'), const [], [XmlElement(XmlName('br'))]),
        );
      }
    } else {
      final nodes = line.map(cleaner.clean).toList();
      // The source's own line breaks only; never trim(), which would also
      // eat the full-width space that indents a Japanese paragraph.
      if (nodes.first case XmlText(:final value)) {
        nodes.first = XmlText(value.replaceFirst(RegExp(r'^[\r\n]+'), ''));
      }
      if (nodes.last case XmlText(:final value)) {
        nodes.last = XmlText(value.replaceFirst(RegExp(r'[\r\n]+$'), ''));
      }
      out.add(XmlElement(XmlName('p'), const [], nodes));
    }
    line = [];
  }

  for (final node in children) {
    if (node is XmlElement) {
      final name = node.name.local;
      final note = _noteText(node);
      if (name == 'br') {
        endLine(keepBlank: true);
        continue;
      }
      if (note != null && _breakNotes.any(note.contains)) {
        endLine(keepBlank: false);
        out.add(_Break());
        continue;
      }
      if (note != null && _droppedNotes.any(note.contains)) continue;
      if (name == 'script') continue;
      if (_blockElements.contains(name) && !_isInlineHeading(node)) {
        endLine(keepBlank: false);
        out.add(
          name == 'div'
              ? XmlElement(
                  XmlName('div'),
                  _attributes(node),
                  _blocks(node.children, cleaner).where((n) => n is! _Break),
                )
              : cleaner.clean(node),
        );
        continue;
      }
    }
    line.add(node);
  }
  endLine(keepBlank: false);
  return out;
}

/// The large or medium heading [node] is, or wraps: Aozora puts headings in
/// an indent div (`<div class="jisage_5"><h4 …>`).
XmlElement? _chapterHeading(XmlNode node) {
  if (node is! XmlElement) return null;
  final name = node.name.local;
  if (name == 'h3' || name == 'h4') return node;
  if (name != 'div') return null;
  final children = node.childElements
      .where((e) => !_isBlankParagraph(e))
      .toList();
  return children.length == 1 ? _chapterHeading(children.single) : null;
}

bool _isBlankParagraph(XmlNode node) =>
    node is XmlElement &&
    node.name.local == 'p' &&
    node.children.every((c) => c is XmlElement && c.name.local == 'br');

/// Splits [blocks] at page-break notes and chapter headings, cutting
/// oversized chapters at a paragraph; each chapter comes back serialized,
/// with the text of the heading it starts with.
List<({String? label, String body})> _chapters(List<XmlNode> blocks) {
  final chapters = <({String? label, String body})>[];
  String? label;
  final current = <String>[];
  var size = 0;
  void endChapter() {
    while (current.isNotEmpty && current.last == _blankParagraph) {
      current.removeLast();
    }
    if (current.isNotEmpty) {
      chapters.add((label: label, body: current.join('\n')));
    }
    current.clear();
    label = null;
    size = 0;
  }

  for (final block in blocks) {
    if (block is _Break) {
      endChapter();
      continue;
    }
    final heading = _chapterHeading(block);
    if (heading != null ||
        (size > _maxChapterChars &&
            block is XmlElement &&
            block.name.local == 'p')) {
      endChapter();
      if (heading != null) label = _headingText(heading);
    }
    final xml = block.toXmlString();
    if (current.isEmpty && xml == _blankParagraph) continue;
    current.add(xml);
    size += xml.length;
  }
  endChapter();
  return chapters;
}

final _blankParagraph = XmlElement(XmlName('p'), const [], [
  XmlElement(XmlName('br')),
]).toXmlString();

/// A heading's text without its readings.
String _headingText(XmlElement heading) {
  final copy = heading.copy();
  for (final rt in copy.findAllElements('rt').toList()) {
    rt.parent?.children.remove(rt);
  }
  return copy.innerText.trim();
}

String _escape(String text) =>
    const HtmlEscape(HtmlEscapeMode.element).convert(text);

String _xhtml({
  required String title,
  required String body,
  bool stylesheet = false,
}) =>
    '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="ja" lang="ja">
<head>
<meta charset="UTF-8"/>
<title>${_escape(title)}</title>
${stylesheet ? '<link rel="stylesheet" type="text/css" href="../style.css"/>' : ''}
</head>
<body>
$body
</body>
</html>
''';

String _nav(String title, List<_Doc> docs) => _xhtml(
  title: title,
  body:
      '''<nav epub:type="toc" id="toc">
<ol>
${[for (final doc in docs)
        if (doc.label.isNotEmpty) '<li><a href="text/${doc.id}.xhtml">${_escape(doc.label)}</a></li>'].join('\n')}
</ol>
</nav>''',
);

String _opf(AozoraWork work, List<_Doc> docs, Iterable<String> imageNames) {
  const xhtmlType = 'application/xhtml+xml';
  final items = [
    '<item id="nav" href="nav.xhtml" media-type="$xhtmlType" properties="nav"/>',
    '<item id="style" href="style.css" media-type="text/css"/>',
    for (final doc in docs)
      '<item id="${doc.id}" href="text/${doc.id}.xhtml" media-type="$xhtmlType"/>',
    for (final name in imageNames)
      '<item id="img${name.split('.').first}" href="images/$name" '
          'media-type="${lookupMimeType(name) ?? 'image/png'}"/>',
  ];
  return '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid" xml:lang="ja">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:identifier id="bookid">urn:aozora:${work.id}</dc:identifier>
<dc:title>${_escape(work.displayTitle)}</dc:title>
<dc:creator>${_escape(work.author)}</dc:creator>
<dc:language>ja</dc:language>
<dc:source>${_escape(work.cardUrl.toString())}</dc:source>
<meta property="dcterms:modified">2000-01-01T00:00:00Z</meta>
<meta name="primary-writing-mode" content="vertical-rl"/>
</metadata>
<manifest>
${items.join('\n')}
</manifest>
<spine page-progression-direction="rtl">
${[for (final doc in docs) '<itemref idref="${doc.id}"/>'].join('\n')}
</spine>
</package>
''';
}

const _containerXml = '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
<rootfiles>
<rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
</rootfiles>
</container>
''';

const _styleCss = '''@charset "UTF-8";
html {
  writing-mode: vertical-rl;
  -webkit-writing-mode: vertical-rl;
  -epub-writing-mode: vertical-rl;
}
p { margin: 0; }
h1, h2, h3, h4, h5 { font-weight: bold; margin-block: 0.5em; }
h1 { font-size: 1.5em; }
h2 { font-size: 1.15em; }
h3 { font-size: 1.3em; }
h4 { font-size: 1.15em; }
h5 { font-size: 1.05em; }
img.gaiji { width: 1em; height: 1em; }
img.illustration, img.photo { max-width: 100%; max-height: 100%; }
.notes { font-size: 0.75em; }
.warichu, .kaeriten, .okurigana { font-size: 0.7em; }
.futoji, .dogyo-naka-midashi, .dogyo-ko-midashi, .dogyo-o-midashi { font-weight: bold; }
.shatai { font-style: italic; }
em { font-style: normal; }
em.sesame_dot { text-emphasis-style: sesame; -webkit-text-emphasis-style: sesame; }
em.white_sesame_dot { text-emphasis-style: open sesame; -webkit-text-emphasis-style: open sesame; }
em.black_circle { text-emphasis-style: filled circle; -webkit-text-emphasis-style: filled circle; }
em.white_circle { text-emphasis-style: open circle; -webkit-text-emphasis-style: open circle; }
em.underline_solid { text-decoration: underline; }
''';
