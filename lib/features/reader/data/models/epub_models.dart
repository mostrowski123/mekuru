/// Location within an EPUB document.
class EpubLocation {
  final String startCfi;
  final String endCfi;
  final double progress;

  /// Current spine item href and position within it (0..1), when the
  /// bridge could determine them. Used for server progress sync locators.
  final String? href;
  final double? hrefProgression;

  const EpubLocation({
    required this.startCfi,
    required this.endCfi,
    required this.progress,
    this.href,
    this.hrefProgression,
  });

  factory EpubLocation.fromJson(Map<String, dynamic> json) {
    return EpubLocation(
      startCfi: json['startCfi'] as String? ?? '',
      endCfi: json['endCfi'] as String? ?? '',
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      href: json['href'] as String?,
      hrefProgression: (json['hrefProgression'] as num?)?.toDouble(),
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
