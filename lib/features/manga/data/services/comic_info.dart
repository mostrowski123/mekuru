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
