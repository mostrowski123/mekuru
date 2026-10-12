import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mekuru/features/reader/data/services/epub_image_zoom.dart';
import 'package:path/path.dart' as p;

/// A page of the test book: its body, and its spine `properties`.
typedef _Page = (String body, String? properties);

/// Writes an extracted EPUB (OPF in `OEBPS/`, sections `text/s<i>.xhtml`,
/// images in `images/`) and the PNGs named in [sizes].
Future<void> _writeBook(
  Directory dir,
  List<_Page> pages, {
  Map<String, (int, int)> sizes = const {},
  String direction = 'rtl',
}) async {
  Future<void> write(String path, String content) async {
    final file = File(p.join(dir.path, path));
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }

  await write(
    'META-INF/container.xml',
    '<?xml version="1.0"?><container version="1.0" '
        'xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles>'
        '<rootfile full-path="OEBPS/content.opf" '
        'media-type="application/oebps-package+xml"/></rootfiles></container>',
  );
  await write(
    'OEBPS/content.opf',
    '<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" '
        'version="3.0"><metadata/><manifest>'
        '${[for (var i = 0; i < pages.length; i++) '<item id="s$i" href="text/s$i.xhtml" media-type="application/xhtml+xml"/>'].join()}'
        '</manifest><spine page-progression-direction="$direction">'
        '${[for (var i = 0; i < pages.length; i++) pages[i].$2 == null ? '<itemref idref="s$i"/>' : '<itemref idref="s$i" properties="${pages[i].$2}"/>'].join()}'
        '</spine></package>',
  );
  for (var i = 0; i < pages.length; i++) {
    await write(
      'OEBPS/text/s$i.xhtml',
      '<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml" '
          'xmlns:xlink="http://www.w3.org/1999/xlink"><head><title>s</title>'
          '</head><body>${pages[i].$1}</body></html>',
    );
  }
  for (final MapEntry(key: name, value: (w, h)) in sizes.entries) {
    final file = File(p.join(dir.path, 'OEBPS', 'images', name));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(img.encodePng(img.Image(width: w, height: h)));
  }
}

String _img(String name) => '<p><img src="../images/$name" alt=""/></p>';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('epub_zoom_');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  /// The zoomed pictures as `name WxH`, left first.
  Future<List<String>?> zoom(String href, int index, {bool rtl = true}) async =>
      (await epubZoomImages(
        dir.path,
        href,
        index,
        rtl: rtl,
      ))?.map((i) => '${p.basename(i.path)} ${i.width}x${i.height}').toList();

  test('an image alone on its page', () async {
    await _writeBook(dir, [(_img('a.png'), null)], sizes: {'a.png': (30, 40)});
    expect(await zoom('text/s0.xhtml', 0), ['a.png 30x40']);
  });

  test('the image at the index on a page with several', () async {
    await _writeBook(
      dir,
      [
        (
          '<p>文<img src="../images/a.png"/>と'
              '<svg><image xlink:href="../images/b.png" width="9" height="9"/></svg></p>',
          null,
        ),
      ],
      sizes: {'a.png': (30, 40), 'b.png': (50, 20)},
    );
    expect(await zoom('text/s0.xhtml', 1), ['b.png 50x20']);
  });

  test('right-to-left halves join, left first, from either half', () async {
    await _writeBook(
      dir,
      [
        (_img('cover.png'), null),
        (_img('r.png'), 'rendition:page-spread-right'),
        (_img('l.png'), 'rendition:page-spread-left'),
      ],
      sizes: {'cover.png': (10, 10), 'r.png': (30, 40), 'l.png': (31, 40)},
    );
    const both = ['l.png 31x40', 'r.png 30x40'];
    expect(await zoom('text/s1.xhtml', 0), both);
    expect(await zoom('text/s2.xhtml', 0), both);
  });

  test('left-to-right halves join, left first', () async {
    await _writeBook(
      dir,
      [
        (_img('l.png'), 'page-spread-left'),
        (_img('r.png'), 'page-spread-right'),
      ],
      sizes: {'l.png': (31, 40), 'r.png': (30, 40)},
      direction: 'ltr',
    );
    const both = ['l.png 31x40', 'r.png 30x40'];
    expect(await zoom('text/s0.xhtml', 0, rtl: false), both);
    expect(await zoom('text/s1.xhtml', 0, rtl: false), both);
  });

  test('a half without its other half shows alone', () async {
    await _writeBook(
      dir,
      [(_img('r.png'), 'page-spread-right'), (_img('next.png'), null)],
      sizes: {'r.png': (30, 40), 'next.png': (30, 40)},
    );
    expect(await zoom('text/s0.xhtml', 0), ['r.png 30x40']);
  });

  test('a text page beside a half is not joined', () async {
    await _writeBook(
      dir,
      [(_img('r.png'), 'page-spread-right'), ('<p>本文</p>', 'page-spread-left')],
      sizes: {'r.png': (30, 40)},
    );
    expect(await zoom('text/s0.xhtml', 0), ['r.png 30x40']);
  });

  test('nothing for a bad index or a missing book folder', () async {
    await _writeBook(dir, [(_img('a.png'), null)], sizes: {'a.png': (30, 40)});
    expect(await zoom('text/s0.xhtml', 1), isNull);
    expect(await zoom('text/s0.xhtml', -1), isNull);
    expect(await zoom('text/missing.xhtml', 0), isNull);
    await dir.delete(recursive: true);
    expect(await zoom('text/s0.xhtml', 0), isNull);
  });

  test('never reads outside the book folder', () async {
    await File(
      p.join(dir.parent.path, 'outside_${p.basename(dir.path)}.png'),
    ).writeAsBytes(img.encodePng(img.Image(width: 5, height: 5)));
    await _writeBook(dir, [
      (
        '<p><img src="../../../outside_${p.basename(dir.path)}.png"/></p>',
        null,
      ),
    ]);
    expect(await zoom('text/s0.xhtml', 0), isNull);
    expect(
      await zoom('../../../${p.basename(dir.path)}/OEBPS/text/s0.xhtml', 0),
      isNull,
    );
  });
}
