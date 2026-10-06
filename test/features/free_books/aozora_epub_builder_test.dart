import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/free_books/data/models/aozora_work.dart';
import 'package:mekuru/features/free_books/data/services/aozora_epub_builder.dart';
import 'package:mekuru/features/library/data/services/epub_parser.dart';
import 'package:path/path.dart' as p;

import '../../shared/saf_image_fixtures.dart';

/// A trimmed Aozora XHTML (Shift_JIS, Run Melos) with a heading in an indent
/// div, ruby, gaiji images, a page-break note, bottom alignment and the
/// bibliographic block.
final _fixtureBytes = File('test/shared/aozora_sample.html').readAsBytesSync();

const _gaiji = '../../../gaiji/1-84/1-84-77.png';
const _missingGaiji = '../../../gaiji/1-02/1-02-03.png';

AozoraWork _work({String? subtitle}) => AozoraWork(
  id: 1567,
  title: '走れメロス',
  subtitle: subtitle,
  titleReading: 'はしれメロス',
  author: '太宰 治',
  authorReading: 'だざい おさむ',
  xhtmlPath: '000035/files/1567_14913.html',
  genre: AozoraGenre.fiction,
  spelling: AozoraSpelling.modern,
  charCount: 9913,
  jlptEstimate: 1,
  popularity: 1,
);

Uint8List _epub({AozoraWork? work}) => buildAozoraEpub(
  xhtml: decodeAozoraXhtml(_fixtureBytes),
  work: work ?? _work(),
  images: {_gaiji: Uint8List.fromList(kTransparentPng)},
);

Archive _build({AozoraWork? work}) =>
    ZipDecoder().decodeBytes(_epub(work: work));

String _text(Archive archive, String name) =>
    utf8.decode(archive.findFile(name)!.readBytes()!);

void main() {
  group('decodeAozoraXhtml', () {
    test('decodes Shift_JIS', () {
      final xhtml = decodeAozoraXhtml(_fixtureBytes);
      expect(xhtml, contains('メロスは激怒した。'));
      expect(xhtml, contains('邪智暴虐'));
    });

    test('honours a UTF-8 declaration', () {
      final bytes = utf8.encode(
        '<?xml version="1.0" encoding="UTF-8"?><p>走れ</p>',
      );
      expect(decodeAozoraXhtml(bytes), contains('走れ'));
    });
  });

  group('decodeCp932', () {
    test('decodes the IBM extensions, two bytes each', () {
      // 髙 (IBM, FB FC), 纊 and ⅰ (NEC-selected IBM, ED 40 and EE EF),
      // ⅰ again (IBM, FA 40), each followed by a plain あ.
      expect(
        decodeCp932([
          0xFB, 0xFC, 0x82, 0xA0, //
          0xED, 0x40, 0x82, 0xA0,
          0xEE, 0xEF, 0x82, 0xA0,
          0xFA, 0x40, 0x82, 0xA0,
        ]),
        '髙あ纊あⅰあⅰあ',
      );
    });

    test('reads a user-defined character as one unknown character', () {
      expect(decodeCp932([0xF0, 0x40, 0x41]), '\u{FFFD}A');
    });

    test('a lead byte cut off at the end is unknown, not an error', () {
      expect(decodeCp932([0x82, 0xA0, 0x88]), 'あ\u{FFFD}');
      expect(decodeCp932([0xFA]), '\u{FFFD}');
    });
  });

  test('aozoraImageSources lists each image once, as written', () {
    final xhtml = decodeAozoraXhtml(_fixtureBytes);
    expect(aozoraImageSources(xhtml), [_gaiji, _missingGaiji]);
  });

  group('buildAozoraEpub', () {
    final archive = _build();
    final chapters =
        archive.files
            .map((f) => f.name)
            .where((n) => RegExp(r'OEBPS/text/c\d{4}\.xhtml').hasMatch(n))
            .toList()
          ..sort();

    test('starts with an uncompressed mimetype entry', () {
      final first = archive.files.first;
      expect(first.name, 'mimetype');
      expect(utf8.decode(first.readBytes()!), 'application/epub+zip');
      expect(first.compression, CompressionType.none);
    });

    test('writes vertical, right-to-left package metadata', () {
      final opf = _text(archive, 'OEBPS/content.opf');
      expect(opf, contains('<dc:title>走れメロス</dc:title>'));
      expect(opf, contains('<dc:creator>太宰 治</dc:creator>'));
      expect(opf, contains('urn:aozora:1567'));
      expect(opf, contains('<dc:language>ja</dc:language>'));
      expect(opf, contains('content="vertical-rl"'));
      expect(opf, contains('page-progression-direction="rtl"'));
      expect(
        _text(archive, 'OEBPS/style.css'),
        contains('writing-mode: vertical-rl'),
      );
    });

    test('the title includes the subtitle', () {
      final opf = _text(
        _build(work: _work(subtitle: '桐壺')),
        'OEBPS/content.opf',
      );
      expect(opf, contains('<dc:title>走れメロス 桐壺</dc:title>'));
    });

    test('splits at the page-break note and at headings', () {
      // Heading one + its text, then (page break) the rest of that section,
      // then heading two.
      expect(chapters, [
        'OEBPS/text/c0001.xhtml',
        'OEBPS/text/c0002.xhtml',
        'OEBPS/text/c0003.xhtml',
      ]);
      expect(_text(archive, chapters[0]), contains('激怒した'));
      expect(_text(archive, chapters[1]), contains('静かに笑った'));
      expect(_text(archive, chapters[2]), contains('赤面した'));
    });

    test('lists headings in the nav without their readings', () {
      final nav = _text(archive, 'OEBPS/nav.xhtml');
      expect(nav, contains('>一の章</a>'));
      expect(nav, contains('>二</a>'));
      expect(nav, contains('href="text/title.xhtml"'));
      expect(nav, contains('href="text/colophon.xhtml"'));
    });

    test('unwraps rb and drops rp so lookups see clean text', () {
      final body = _text(archive, chapters[0]);
      expect(body, contains('<ruby>邪智暴虐<rt>じゃちぼうぎゃく</rt></ruby>'));
      expect(body, isNot(contains('<rb>')));
      expect(body, isNot(contains('<rp>')));
    });

    test('turns lines into paragraphs and keeps no notes for breaks', () {
      final body = _text(archive, chapters[0]);
      expect(body, contains('<p>　メロスは激怒した。'));
      expect(body, isNot(contains('<br/>　メロス')));
      expect(
        [for (final c in chapters) _text(archive, c)].join(),
        isNot(contains('改ページ')),
      );
    });

    test('makes margins logical so indents work vertically', () {
      final all = [for (final c in chapters) _text(archive, c)].join();
      expect(all, contains('margin-inline-start: 5em'));
      expect(all, contains('margin-inline-end: 1em'));
      expect(all, isNot(contains('margin-left')));
    });

    test('embeds fetched images and falls back to alt text', () {
      final body = _text(archive, chapters[0]);
      expect(body, contains('src="../images/0001.png"'));
      expect(archive.findFile('OEBPS/images/0001.png'), isNotNull);
      expect(
        _text(archive, 'OEBPS/content.opf'),
        contains('id="img0001" href="images/0001.png" media-type="image/png"'),
      );
      expect(body, contains('※(「口＋世」)'));
    });

    test('keeps the credits in a colophon and drops scripts and the card', () {
      final colophon = _text(archive, 'OEBPS/text/colophon.xhtml');
      expect(colophon, contains('底本：「太宰治全集3」'));
      expect(colophon, contains('入力：金川一之'));
      final all = archive.files
          .where((f) => f.name.endsWith('.xhtml'))
          .map((f) => utf8.decode(f.readBytes()!))
          .join();
      expect(all, isNot(contains('<script')));
      expect(all, isNot(contains('図書カード')));
    });

    test('the title page carries the title and author', () {
      final page = _text(archive, 'OEBPS/text/title.xhtml');
      expect(page, contains('走れメロス'));
      expect(page, contains('太宰治'));
    });

    test('is deterministic', () {
      final again = _build();
      for (final file in archive.files) {
        expect(
          again.findFile(file.name)?.readBytes(),
          file.readBytes(),
          reason: file.name,
        );
      }
    });

    test('lists the title once for a work without headings', () {
      final archive = ZipDecoder().decodeBytes(
        buildAozoraEpub(
          xhtml:
              '<html xmlns="http://www.w3.org/1999/xhtml"><body>'
              '<div class="metadata"><h1 class="title">走れメロス</h1></div>'
              '<div class="main_text">メロスは激怒した。<br/></div>'
              '</body></html>',
          work: _work(),
        ),
      );
      final nav = _text(archive, 'OEBPS/nav.xhtml');

      expect('>走れメロス</a>'.allMatches(nav), hasLength(1));
      expect(nav, contains('href="text/title.xhtml"'));
      expect(nav, isNot(contains('href="text/c0001.xhtml"')));
    });

    test('takes the title page from headings outside a metadata div', () {
      // Some files (Little Red Riding Hood, 42311) put the title, author and
      // translator straight in <body>.
      final archive = ZipDecoder().decodeBytes(
        buildAozoraEpub(
          xhtml:
              '<html xmlns="http://www.w3.org/1999/xhtml"><body>'
              '<h1 class="title">走れメロス</h1>'
              '<h2 class="author">太宰治</h2>'
              '<div class="main_text">メロスは激怒した。<br/></div>'
              '</body></html>',
          work: _work(),
        ),
      );
      final titlePage = _text(archive, 'OEBPS/text/title.xhtml');

      expect(titlePage, contains('<h1 class="title">走れメロス</h1>'));
      expect(titlePage, contains('<h2 class="author">太宰治</h2>'));
    });

    test('rejects XHTML without a main text', () {
      expect(
        () => buildAozoraEpub(xhtml: '<html><body/></html>', work: _work()),
        throwsFormatException,
      );
    });

    test(
      'imports through the app EPUB parser as a vertical Japanese book',
      () async {
        final dir = await Directory.systemTemp.createTemp('aozora_epub_test');
        addTearDown(() => dir.delete(recursive: true));
        final epub = File(p.join(dir.path, 'aozora_1567.epub'));
        await epub.writeAsBytes(_epub());
        final metadata = await EpubParser.parseEpub(
          epub.path,
          p.join(dir.path, 'content'),
        );
        expect(metadata.title, '走れメロス');
        expect(metadata.author, '太宰 治');
        expect(metadata.language, 'ja');
        expect(metadata.primaryWritingMode, 'vertical-rl');
        expect(metadata.pageProgressionDirection, 'rtl');
        expect(metadata.hasVerticalCss, isTrue);
      },
    );
  });
}
