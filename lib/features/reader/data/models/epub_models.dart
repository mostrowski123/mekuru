/// Location within an EPUB document.
class EpubLocation {
  final String startCfi;
  final String endCfi;
  final double progress;

  const EpubLocation({
    required this.startCfi,
    required this.endCfi,
    required this.progress,
  });

  factory EpubLocation.fromJson(Map<String, dynamic> json) {
    return EpubLocation(
      startCfi: json['startCfi'] as String? ?? '',
      endCfi: json['endCfi'] as String? ?? '',
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
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
