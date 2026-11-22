import 'dart:convert';

/// Location within an EPUB document.
class EpubLocation {
  /// The reader's place, saved as progress. After a re-layout it can be in
  /// the middle of the page (reader_bridge.js keepPlace()).
  final String startCfi;
  final String endCfi;
  final double progress;

  /// Current spine item href and position within it (0..1), when the
  /// bridge could determine them. Used for server progress sync locators.
  final String? href;
  final double? hrefProgression;

  /// The start of the page on screen, where a bookmark goes; [startCfi]
  /// when not given.
  final String pageStartCfi;

  const EpubLocation({
    required this.startCfi,
    required this.endCfi,
    required this.progress,
    this.href,
    this.hrefProgression,
    String? pageStartCfi,
  }) : pageStartCfi = pageStartCfi ?? startCfi;

  factory EpubLocation.fromJson(Map<String, dynamic> json) {
    return EpubLocation(
      startCfi: json['startCfi'] as String? ?? '',
      endCfi: json['endCfi'] as String? ?? '',
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      href: json['href'] as String?,
      hrefProgression: (json['hrefProgression'] as num?)?.toDouble(),
      pageStartCfi: json['pageStartCfi'] as String?,
    );
  }
}

/// A chapter entry from the EPUB table of contents.
class EpubChapter {
  final String title;
  final String href;
  final String id;
  final List<EpubChapter> subitems;

  const EpubChapter({
    required this.title,
    required this.href,
    required this.id,
    required this.subitems,
  });

  factory EpubChapter.fromJson(Map<String, dynamic> json) {
    return EpubChapter(
      title: json['title'] as String? ?? '',
      href: json['href'] as String? ?? '',
      id: json['id'] as String? ?? '',
      subitems: json['subitems'] is List
          ? (json['subitems'] as List)
                .map((e) => EpubChapter.fromJson(_toStringKeyMap(e)))
                .toList()
          : const [],
    );
  }
}

Map<String, dynamic> _toStringKeyMap(dynamic value) {
  if (value is Map) {
    return value.map((k, v) => MapEntry(k.toString(), v));
  }
  return {};
}

/// Parse a list of chapter JSON objects into [EpubChapter] instances.
List<EpubChapter> parseChapterList(dynamic result) {
  if (result == null) return [];
  final list = result is List ? result : [result];
  return list.map((e) => EpubChapter.fromJson(_toStringKeyMap(e))).toList();
}

/// A table-of-contents entry placed against a position (`tocPlacement` in
/// reader_bridge.js): its spine item (-1 when its href names none) and, in
/// the position's own item, whether its anchor starts after the position
/// (null when that is unknown).
typedef TocPlacement = ({String title, int spine, bool? anchorAfter});

/// The title of the chapter a position in spine item [spine] falls under,
/// or '' when no entry of [toc] (depth first) comes before it: the entry
/// in the latest item not after [spine]. Within item [spine] the last
/// entry whose anchor is not after the position wins, or the item's first
/// entry when its anchors cannot be checked.
String pickChapterTitle(int spine, List<TocPlacement> toc) {
  var title = '';
  var best = -1;
  for (final entry in toc) {
    if (entry.title.isEmpty || entry.spine < 0) continue;
    if (entry.spine > spine || entry.spine < best) continue;
    // Unknown: after the position unless it is the item's first entry.
    if (entry.spine == spine && (entry.anchorAfter ?? best == spine)) continue;
    best = entry.spine;
    title = entry.title;
  }
  return title;
}

/// [pickChapterTitle] for a `tocPlacement` result from reader_bridge.js: a
/// JSON string, or the map it decodes to.
String chapterTitleFromPlacement(Object? raw) {
  final placement = (raw is String ? jsonDecode(raw) : raw) as Map;
  return pickChapterTitle(placement['spine'] as int, [
    for (final entry in placement['toc'] as List)
      (
        title: entry[0] as String,
        spine: entry[1] as int,
        anchorAfter: entry[2] as bool?,
      ),
  ]);
}
