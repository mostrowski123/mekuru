import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/data/services/comic_info.dart';
import 'package:xml/xml.dart';

String _xml(String fields) =>
    '<?xml version="1.0" encoding="utf-8"?>'
    '<ComicInfo xmlns:xsd="http://www.w3.org/2001/XMLSchema">$fields</ComicInfo>';

String? _title({String? series, String? number, String? title}) =>
    ComicInfo.tryParse(
      _xml(
        '${series == null ? '' : '<Series>$series</Series>'}'
        '${number == null ? '' : '<Number>$number</Number>'}'
        '${title == null ? '' : '<Title>$title</Title>'}',
      ),
    )!.title;

void main() {
  group('title', () {
    test('series, number and title', () {
      expect(
        _title(series: '葬送のフリーレン', number: '3', title: '魂の眠る地'),
        '葬送のフリーレン 3 – 魂の眠る地',
      );
    });

    test('empty parts are left out', () {
      expect(_title(series: '葬送のフリーレン', number: '3'), '葬送のフリーレン 3');
      expect(_title(series: '葬送のフリーレン', title: ''), '葬送のフリーレン');
      expect(_title(title: '短編集'), '短編集');
      expect(_title(number: '2'), '2');
    });

    test('a title that repeats the series or the number is dropped', () {
      expect(_title(series: 'A', number: '1', title: 'A'), 'A 1');
      for (final repeat in [
        'Vol. 3',
        'volume 03',
        'Ch.3',
        'Chapter 3',
        'No. 3',
        '#3',
        '第3巻',
        '第03話',
        '3',
      ]) {
        expect(
          _title(series: 'A', number: '3', title: repeat),
          'A 3',
          reason: repeat,
        );
      }
      expect(
        _title(series: 'A', number: '3', title: 'Vol. 13'),
        'A 3 – Vol. 13',
      );
    });

    test('null without series, number or title', () {
      expect(ComicInfo.tryParse(_xml('<Writer>someone</Writer>'))!.title, null);
    });
  });

  test('direction from the Manga field', () {
    String? direction(String? manga) => ComicInfo.tryParse(
      _xml(manga == null ? '' : '<Manga>$manga</Manga>'),
    )!.direction;
    expect(direction('YesAndRightToLeft'), 'rtl');
    expect(direction('No'), 'ltr');
    expect(direction('Yes'), isNull);
    expect(direction('Unknown'), isNull);
    expect(direction(null), isNull);
  });

  test('double pages by their 0-based image number', () {
    final info = ComicInfo.tryParse(
      _xml(
        '<Pages>'
        '<Page Image="0" Type="FrontCover"/>'
        '<Page Image="3" DoublePage="True"/>'
        '<Page Image="5" DoublePage="true"/>'
        '<Page Image="6" DoublePage="1"/>'
        '<Page Image="7" DoublePage="False"/>'
        '<Page Image="-1" DoublePage="True"/>'
        '<Page DoublePage="True"/>'
        '</Pages>',
      ),
    )!;
    expect(info.doublePages, {3, 5, 6});
  });

  test('a byte order mark is fine', () {
    expect(ComicInfo.tryParse('\uFEFF${_xml('<Title>題</Title>')}')!.title, '題');
  });

  test('malformed XML is no ComicInfo, never an error', () {
    expect(ComicInfo.tryParse('<ComicInfo><Title>broken'), isNull);
    expect(ComicInfo.tryParse(''), isNull);
    expect(ComicInfo.tryParse('<Other/>'), isNull);
  });

  group('write', () {
    test('writes the fields in schema order, escaped', () {
      final root = XmlDocument.parse(
        ComicInfo.write(
          title: 'Tom & Jerry <1>',
          rtl: true,
          pageCount: 3,
          doublePages: {1, 2},
        ),
      ).rootElement;

      expect(root.localName, 'ComicInfo');
      expect(
        [for (final e in root.childElements) e.localName],
        ['Title', 'PageCount', 'Manga', 'Pages'],
      );
      expect(root.getElement('Title')!.innerText, 'Tom & Jerry <1>');
      expect(root.getElement('PageCount')!.innerText, '3');
      expect(root.getElement('Manga')!.innerText, 'YesAndRightToLeft');
      expect(
        [
          for (final page in root.getElement('Pages')!.childElements)
            '${page.getAttribute('Image')} ${page.getAttribute('DoublePage')}',
        ],
        ['1 True', '2 True'],
      );
    });

    test('reads back what it writes', () {
      final info = ComicInfo.tryParse(
        ComicInfo.write(
          title: '題名',
          rtl: false,
          pageCount: 2,
          doublePages: {0},
        ),
      )!;
      expect(info.title, '題名');
      expect(info.direction, 'ltr');
      expect(info.doublePages, {0});
    });

    test('leaves Pages out when no page is double', () {
      final root = XmlDocument.parse(
        ComicInfo.write(title: 'T', rtl: true, pageCount: 1, doublePages: {}),
      ).rootElement;
      expect(root.getElement('Pages'), isNull);
    });
  });
}
