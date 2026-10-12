// A light novel's image pages on a real WebView: a cover-like portrait
// illustration, a two-page spread stored as one wide image (the issue #37
// book has them as 1600x851 JPEGs in an otherwise vertical book), a small
// ornament, and a text page with an inline gaiji image.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mekuru/features/reader/presentation/widgets/custom_epub_controller.dart';
import 'package:path/path.dart' as p;

import '../test_helpers.dart';

const imagePagesTitle = '挿絵テスト';

/// Sections: `portrait.xhtml` (a horizontal-tb illustration page in an `img`),
/// `spread.xhtml` (vertical-rl, the wide image in an `svg` with no viewBox,
/// as calibre writes them), `ornament.xhtml` (a 40x20 image alone) and
/// `text.xhtml` (text with a 128 px inline image). The OPF asks for
/// `rendition:spread both`, which put pages two-up on wide screens.
Future<String> writeImagePagesEpub(Directory dir) async {
  final archive = Archive();

  void addBytes(String path, List<int> bytes) =>
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
  void addFile(String path, String content) =>
      addBytes(path, utf8.encode(content));
  void addPng(String name, int width, int height) => addBytes(
    'OEBPS/$name',
    img.encodePng(
      img.Image(width: width, height: height)
        ..clear(img.ColorRgb8(90, 90, 140)),
    ),
  );

  addFile(
    'META-INF/container.xml',
    '<?xml version="1.0" encoding="UTF-8"?>'
        '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
        '<rootfiles>'
        '<rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>'
        '</rootfiles>'
        '</container>',
  );
  addFile(
    'OEBPS/content.opf',
    '<?xml version="1.0" encoding="UTF-8"?>'
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">'
        '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:title>$imagePagesTitle</dc:title>'
        '<dc:language>ja</dc:language>'
        '<dc:identifier id="bookid">urn:uuid:00000000-0000-0000-0000-000000000071</dc:identifier>'
        '<meta property="rendition:spread">both</meta>'
        '</metadata>'
        '<manifest>'
        '<item id="portrait" href="portrait.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="spread" href="spread.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="ornament" href="ornament.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="text" href="text.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="p1" href="portrait.png" media-type="image/png"/>'
        '<item id="p2" href="wide.png" media-type="image/png"/>'
        '<item id="p3" href="ornament.png" media-type="image/png"/>'
        '<item id="p4" href="gaiji.png" media-type="image/png"/>'
        '<item id="css" href="vertical.css" media-type="text/css"/>'
        '</manifest>'
        '<spine page-progression-direction="rtl">'
        '<itemref idref="portrait"/>'
        '<itemref idref="spread"/>'
        '<itemref idref="ornament"/>'
        '<itemref idref="text"/>'
        '</spine>'
        '</package>',
  );
  addFile(
    'OEBPS/vertical.css',
    'html { writing-mode: vertical-rl; -epub-writing-mode: vertical-rl; }\n',
  );
  addPng('portrait.png', 600, 900);
  addPng('wide.png', 1030, 736);
  addPng('ornament.png', 40, 20);
  addPng('gaiji.png', 128, 128);

  String page(String name, String body, {bool vertical = false}) =>
      '<?xml version="1.0" encoding="UTF-8" standalone="no"?>'
      '<!DOCTYPE html>'
      '<html xmlns="http://www.w3.org/1999/xhtml" '
      'xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="ja"'
      '${vertical ? '' : ' style="writing-mode: horizontal-tb"'}>'
      '<head><title>$name</title>'
      '${vertical ? '<link href="vertical.css" rel="stylesheet" type="text/css"/>' : ''}'
      '</head>'
      '<body>$body</body>'
      '</html>';

  addFile(
    'OEBPS/portrait.xhtml',
    page(
      'portrait',
      '<div class="main"><h4 id="n1"></h4><div class="align-center">'
          '<p><img class="fit" src="portrait.png" alt=""/></p></div></div>',
    ),
  );
  addFile(
    'OEBPS/spread.xhtml',
    page(
      'spread',
      '<div class="main">'
          '<svg xmlns="http://www.w3.org/2000/svg" '
          'xmlns:xlink="http://www.w3.org/1999/xlink" version="1.1" '
          'width="100%" height="100%" preserveAspectRatio="none">'
          '<image width="1030" height="736" xlink:href="wide.png"/></svg>'
          '</div>',
      vertical: true,
    ),
  );
  addFile(
    'OEBPS/ornament.xhtml',
    page('ornament', '<p><img src="ornament.png" alt=""/></p>'),
  );
  final words = '山の中に深い穴がありました。村の人たちは、必要な時いつでもこの穴の口に来ました。' * 6;
  addFile(
    'OEBPS/text.xhtml',
    page(
      'text',
      '<p>$words<img class="gaiji" src="gaiji.png" alt=""/>$words</p>',
      vertical: true,
    ),
  );

  final epubPath = p.join(dir.path, 'image_pages.epub');
  await File(epubPath).writeAsBytes(ZipEncoder().encode(archive));
  return epubPath;
}

/// Shows [href] and waits until the reader is on it.
Future<void> showSection(
  WidgetTester tester,
  CustomEpubController controller,
  String href,
) async {
  await controller.debugEvaluateJavascript('rendition.display("$href"); true');
  for (var i = 0; ; i++) {
    final at = await controller.debugEvaluateJavascript(
      'rendition.location ? rendition.location.start.href : ""',
    );
    if (at == href) break;
    if (i == 40) fail('the reader never showed $href (it is on $at)');
    await tester.pump(const Duration(milliseconds: 250));
  }
  // Images decode and pages re-expand after the section is shown.
  await tester.pump(const Duration(seconds: 1));
}

/// Geometry of the first [selector] match in the section on screen, in the
/// section's own coordinates. `painted` is where the picture itself lands:
/// the `<image>` inside an svg, or the object-fit box of an img.
Future<Map<String, dynamic>> imageState(
  CustomEpubController controller,
  String selector,
) => evalJson(
  controller,
  '(function () {'
  '  var c = rendition.getContents()[0], L = rendition._layout;'
  '  var el = c.document.querySelector(${jsonEncode(selector)});'
  '  var r = el.getBoundingClientRect(), painted;'
  '  if (el.tagName.toLowerCase() === "svg") {'
  '    painted = el.querySelector("image").getBoundingClientRect();'
  '  } else {'
  '    var s = Math.min(r.width / el.naturalWidth, r.height / el.naturalHeight);'
  '    var pw = el.naturalWidth * s, ph = el.naturalHeight * s;'
  '    painted = {left: r.left + (r.width - pw) / 2,'
  '      top: r.top + (r.height - ph) / 2, width: pw, height: ph};'
  '  }'
  '  var cs = c.window.getComputedStyle(el), loc = rendition.currentLocation();'
  '  var view = rendition.manager.views.first();'
  '  return JSON.stringify({'
  '    W: L.width, H: L.height, spread: L._spread,'
  '    x: r.left, y: r.top, w: r.width, h: r.height,'
  '    px: painted.left, py: painted.top, pw: painted.width, ph: painted.height,'
  '    fit: cs.objectFit, position: cs.objectPosition,'
  '    inlineStyle: el.getAttribute("style") || "",'
  '    total: loc.start ? loc.start.displayed.total : null,'
  '    frameW: view.width(), frameH: view.height()'
  '  });'
  '})()',
);

/// The image fills the page: the section is one page (one screen in scroll
/// view), the image's box is that page, and the picture is centred in it.
void expectFillsPage(Map<String, dynamic> s) {
  double v(String key) => (s[key] as num).toDouble();
  expect(v('frameW'), closeTo(v('W'), 1), reason: 'section width: $s');
  expect(v('frameH'), closeTo(v('H'), 1), reason: 'section height: $s');
  expect(v('x'), closeTo(0, 1), reason: '$s');
  expect(v('y'), closeTo(0, 1), reason: '$s');
  expect(v('w'), closeTo(v('W'), 1), reason: '$s');
  expect(v('h'), closeTo(v('H'), 1), reason: '$s');
  expectCentred(s, prefix: 'p');
}

/// The box at `<prefix>x`, `<prefix>y`, `<prefix>w`, `<prefix>h` in [s] is
/// centred on the `W` x `H` page and, when [touching], meets two opposite
/// edges of it.
void expectCentred(
  Map<String, dynamic> s, {
  String prefix = '',
  bool touching = true,
}) {
  double v(String key) => (s[key] as num).toDouble();
  final w = v('${prefix}w'), h = v('${prefix}h');
  expect(v('${prefix}x') + w / 2, closeTo(v('W') / 2, 1), reason: '$s');
  expect(v('${prefix}y') + h / 2, closeTo(v('H') / 2, 1), reason: '$s');
  if (touching) {
    expect(
      (w - v('W')).abs() < 1 || (h - v('H')).abs() < 1,
      isTrue,
      reason: 'the box should meet two edges: $s',
    );
  }
}
