import 'dart:convert';

/// A node of a Yomitan structured-content glossary, parsed once for display.
sealed class ScNode {
  const ScNode();
}

class ScText extends ScNode {
  const ScText(this.text);

  final String text;
}

/// A tag node such as `div`, `ul`, `li`, `span`, `ruby`, `a` or `table`.
class ScElement extends ScNode {
  const ScElement({
    required this.tag,
    this.data = const {},
    this.style = const {},
    this.href,
    this.title,
    this.open = false,
    this.children = const [],
  });

  final String tag;

  /// `data` attributes; Yomitan renders them as `data-sc-<key>`, and styles
  /// (Jitendex's CSS) key on them.
  final Map<String, String> data;

  /// Inline `style` values as given, e.g. `{'listStyleType': '"①"'}`.
  final Map<String, Object?> style;
  final String? href;
  final String? title;

  /// `details` only: shown expanded at first.
  final bool open;
  final List<ScNode> children;

  String? get content => data['content'];
}

/// An `img` node or an image glossary item. [path] points into the
/// dictionary's media (the zip path).
class ScImage extends ScNode {
  const ScImage({
    required this.path,
    this.width,
    this.height,
    this.inEm = false,
    this.alt,
    this.title,
    this.monochrome = false,
    this.background = false,
    this.collapsed = false,
  });

  factory ScImage.fromJson(Map<String, dynamic> json) => ScImage(
    path: json['path'] as String,
    width: _number(json['width']),
    height: _number(json['height']),
    inEm: json['sizeUnits'] == 'em',
    alt: _string(json['alt']),
    title: _string(json['title']) ?? _string(json['description']),
    monochrome: json['appearance'] == 'monochrome',
    background: json['background'] == true,
    collapsed: json['collapsed'] == true,
  );

  final String path;
  final double? width;
  final double? height;

  /// [width] and [height] are multiples of the font size, not pixels.
  final bool inEm;
  final String? alt;
  final String? title;

  /// Drawn in the text color (glyph images).
  final bool monochrome;

  /// Drawn on a light backdrop, for transparent images in dark mode.
  final bool background;
  final bool collapsed;
}

/// Parses a stored glossaries column (a JSON list of plain strings and
/// JSON-encoded objects) into display nodes, one entry per item.
///
/// Returns null when there is nothing structured to lay out — every item
/// plain or text, or the JSON unreadable — so callers keep the plain-text
/// path for those rows.
List<ScNode>? parseRichGlossaries(String glossaries) {
  final List<dynamic> items;
  try {
    items = jsonDecode(glossaries) as List<dynamic>;
  } catch (_) {
    return null;
  }
  final nodes = [
    for (final item in items) item is String ? _parseItem(item) : null,
  ];
  if (nodes.every((node) => node == null || node is ScText)) return null;
  // Each item its own block, as Yomitan lists them: plain glosses beside
  // structured content would otherwise run together.
  return [
    for (final (i, node) in nodes.indexed)
      if (node == null || node is ScText)
        ScElement(tag: 'div', children: [node ?? ScText('${items[i]}')])
      else
        node,
  ];
}

/// The parameters of a `?query=…` lookup link: `query`, and Jitendex's
/// `primary_reading`. Null for other links and for an empty query.
Map<String, String>? lookupLink(String? href) {
  if (href == null || !href.startsWith('?')) return null;
  try {
    // Uri.parse percent-encodes raw text first; JMdict's queries are raw.
    final params = Uri.parse(href).queryParameters;
    return (params['query'] ?? '').isEmpty ? null : params;
  } on FormatException {
    return null;
  }
}

/// The text of a quoted CSS `listStyleType` such as Jitendex's `"①"` or
/// JMdict's `'📝 '` ('' when quoted but empty); null when not quoted.
String? quotedListMarker(Object? listStyleType) => listStyleType is String
    ? _quotedMarker.firstMatch(listStyleType)?.group(2)?.trim()
    : null;

final _quotedMarker = RegExp(r'''^\s*(["'])(.*)\1\s*$''');

// Attribute values, read without casts: a hand-imported dictionary is not
// checked against Yomitan's schema, and a wrong type must not break the row.
String? _string(Object? value) => value is String ? value : null;

double? _number(Object? value) => value is num ? value.toDouble() : null;

/// A structured-content, text or image object; null for a plain string or
/// an object of another kind.
ScNode? _parseItem(String item) {
  if (!item.startsWith('{')) return null;
  final Object? json;
  try {
    json = jsonDecode(item);
  } catch (_) {
    return null;
  }
  if (json is! Map<String, dynamic>) return null;
  return switch (json['type']) {
    'structured-content' => ScElement(
      tag: 'div',
      children: _parseContent(json['content']),
    ),
    'text' => ScText(json['text']?.toString() ?? ''),
    'image' when json['path'] is String => ScImage.fromJson(json),
    'image' => const ScText(''),
    _ => null,
  };
}

List<ScNode> _parseContent(Object? content) {
  if (content == null) return const [];
  if (content is String) return [ScText(content)];
  if (content is num || content is bool) return [ScText(content.toString())];
  if (content is List) return [for (final c in content) ..._parseContent(c)];
  if (content is! Map<String, dynamic>) return const [];

  final tag = content['tag'];
  if (tag is! String) return const [];
  if (tag == 'img') {
    return content['path'] is String ? [ScImage.fromJson(content)] : const [];
  }
  final data = content['data'];
  final style = content['style'];
  return [
    ScElement(
      tag: tag,
      data: data is Map
          ? {for (final e in data.entries) e.key.toString(): e.value.toString()}
          : const {},
      style: style is Map<String, dynamic> ? style : const {},
      href: _string(content['href']),
      title: _string(content['title']),
      open: content['open'] == true,
      children: _parseContent(content['content']),
    ),
  ];
}
