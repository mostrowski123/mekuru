import 'package:xml/xml.dart';

/// What Mekuru reads from a comic archive's ComicInfo.xml (the ComicRack
/// schema that Komga, Kavita and Mihon use).
class ComicInfo {
  /// "Series Number – Title", leaving out empty parts and a Title that only
  /// repeats the Series or the Number; null when it names none of the three.
  final String? title;

  /// `rtl` for `<Manga>YesAndRightToLeft</Manga>`, `ltr` for `No`, null
  /// otherwise (the reader's global setting decides).
  final String? direction;

  /// The 0-based numbers of the pages marked as double pages.
  final Set<int> doublePages;

  const ComicInfo({this.title, this.direction, this.doublePages = const {}});

  /// Null for anything that is not a ComicInfo document. Never throws, so a
  /// bad file can't fail an import.
  static ComicInfo? tryParse(String xml) {
    try {
      final root = XmlDocument.parse(
        xml.replaceFirst('\uFEFF', ''),
      ).rootElement;
      if (root.localName != 'ComicInfo') return null;
      String? field(String name) {
        final text = root.getElement(name)?.innerText.trim();
        return text == null || text.isEmpty ? null : text;
      }

      return ComicInfo(
        title: _title(field('Series'), field('Number'), field('Title')),
        direction: switch (field('Manga')) {
          'YesAndRightToLeft' => 'rtl',
          'No' => 'ltr',
          _ => null,
        },
        doublePages: {
          for (final page in root.findAllElements('Page'))
            if (const {
              'True',
              'true',
              '1',
            }.contains(page.getAttribute('DoublePage')))
              ?int.tryParse(page.getAttribute('Image') ?? ''),
        }..removeWhere((image) => image < 0),
      );
    } catch (_) {
      return null;
    }
  }

  /// A ComicInfo.xml for an exported comic: its [title], [rtl] as the Manga
  /// field, its [pageCount], and the 0-based [doublePages], in schema order.
  static String write({
    required String title,
    required bool rtl,
    required int pageCount,
    required Set<int> doublePages,
  }) {
    final builder = XmlBuilder()
      ..processing('xml', 'version="1.0" encoding="utf-8"');
    builder.element(
      'ComicInfo',
      nest: () {
        builder
          ..element('Title', nest: title)
          ..element('PageCount', nest: pageCount)
          ..element('Manga', nest: rtl ? 'YesAndRightToLeft' : 'No');
        if (doublePages.isEmpty) return;
        builder.element(
          'Pages',
          nest: () {
            for (final image in doublePages.toList()..sort()) {
              builder.element(
                'Page',
                attributes: {'Image': '$image', 'DoublePage': 'True'},
              );
            }
          },
        );
      },
    );
    return builder.buildDocument().toXmlString(pretty: true);
  }

  static String? _title(String? series, String? number, String? title) {
    final n = number?.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final repeatsNumber =
        n != null &&
        title != null &&
        RegExp(
          '^(vol(ume)?|ch(apter)?|no|#|第)?[\\s.]*0*${RegExp.escape(n)}(巻|話)?\$',
          caseSensitive: false,
        ).hasMatch(title);
    final ownTitle = title == series || repeatsNumber ? null : title;
    final head = [?series, ?number].join(' ');
    final parts = [if (head.isNotEmpty) head, ?ownTitle];
    return parts.isEmpty ? null : parts.join(' – ');
  }
}
