import 'dart:convert';

import 'package:mekuru/features/dictionary/data/services/structured_content.dart';

/// Utility for parsing glossary entries stored as JSON strings.
///
/// Glossary items can be either plain strings or structured-content objects
/// (e.g. from Yomitan dictionaries like NEW斎藤和英大辞典), stored as
/// themselves or, in rows imported before 1.47, as JSON strings.
/// This parser extracts human-readable text from all of them.
class GlossaryParser {
  /// Shown instead of raw JSON when a stored glossary cannot be decoded
  /// (e.g. truncated by a partial write). Glossary content itself is not
  /// localized, so a plain-English constant is consistent.
  static const unreadableDefinitionPlaceholder = '(unreadable definition)';

  /// Parse a glossaries JSON string into a list of human-readable definitions.
  ///
  /// The [glossariesJson] is a JSON-encoded list where each element is either:
  /// - A plain string definition (returned as-is)
  /// - A structured-content object (text is extracted recursively)
  static List<String> parse(String glossariesJson) {
    try {
      final List<dynamic> jsonList = jsonDecode(glossariesJson);
      return jsonList
          .map((item) => _itemText(item, decorate: true))
          .where((text) => text.isNotEmpty)
          .toList();
    } catch (_) {
      // Corrupt JSON would render as JSON soup — show a placeholder instead.
      // Plain non-JSON strings pass through unchanged.
      final trimmed = glossariesJson.trim();
      if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
        return const [unreadableDefinitionPlaceholder];
      }
      return [glossariesJson];
    }
  }

  /// Lowercase plain-text rendering of decoded glossary [items] (each a
  /// plain string or a structured-content object), one gloss per line,
  /// without display decorations.
  ///
  /// Stored in dictionary_entries.search_text and tokenized by the
  /// English-search FTS index. The line structure matters — the query side
  /// detects "the query is exactly one of this entry's glosses" via
  /// newline-bounded matching.
  static String searchTextFromItems(List<Object?> items) {
    final lines = <String>[];
    for (final item in items) {
      final text = _itemText(item, decorate: false);
      for (var line in text.split('\n')) {
        line = line.trim();
        if (line.isNotEmpty) {
          lines.add(line.toLowerCase());
        }
      }
    }
    // Rows with glossaries but nothing to index (Jitendex redirects) get a
    // blank, not '': the launch-time backfill re-reads every '' row.
    if (lines.isEmpty) return items.isEmpty ? '' : ' ';
    return lines.join('\n');
  }

  /// [searchTextFromItems] for a stored glossaries JSON string.
  ///
  /// Undecodable JSON yields an empty string — a display placeholder is
  /// useful on screen but would only pollute the search index.
  static String searchText(String glossariesJson) {
    try {
      final List<dynamic> jsonList = jsonDecode(glossariesJson);
      return searchTextFromItems(jsonList);
    } catch (_) {
      final trimmed = glossariesJson.trim();
      if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
        return '';
      }
      return searchTextFromItems([glossariesJson]);
    }
  }

  /// The entry a glossary only points to: Jitendex lists some spellings as
  /// just "⟶ 労働相", a `?query=…` link to the entry with the definitions.
  /// Null when the glossary has text of its own or no such link.
  static ({String expression, String reading})? redirectTarget(
    String glossariesJson,
  ) {
    if (parse(glossariesJson).isNotEmpty) return null;
    final link = _firstLookupLink(parseRichGlossaries(glossariesJson) ?? []);
    if (link == null) return null;
    return (expression: link['query']!, reading: link['primary_reading'] ?? '');
  }

  static Map<String, String>? _firstLookupLink(List<ScNode> nodes) {
    for (final node in nodes) {
      if (node is! ScElement) continue;
      final link = node.tag == 'a' ? lookupLink(node.href) : null;
      if (link ?? _firstLookupLink(node.children) case final found?) {
        return found;
      }
    }
    return null;
  }

  /// The readable text of one glossary item: a plain string as-is, the
  /// text of a structured-content, text or image object, and any other
  /// object as its JSON.
  static String _itemText(Object? item, {required bool decorate}) {
    final json = decodeGlossaryItem(item);
    if (json is Map<String, dynamic>) {
      switch (json['type']) {
        case 'structured-content':
          // Empty content shows nothing, as on screen.
          return _extractText(json['content'], decorate: decorate);
        case 'text':
          return json['text']?.toString() ?? '';
        case 'image':
          return '';
      }
    }
    return item is String ? item : jsonEncode(item);
  }

  /// Recursively extract text content from a structured-content value.
  ///
  /// The content can be:
  /// - A plain string
  /// - A list of mixed strings and tag objects
  /// - A tag object with its own content
  ///
  /// With [decorate], list items get a display bullet; without, the raw
  /// gloss lines come back undecorated (the search-index shape).
  static String _extractText(dynamic content, {required bool decorate}) {
    if (content == null) return '';
    if (content is String) return content;
    if (content is num || content is bool) return content.toString();

    if (content is List) {
      final parts = <String>[];
      for (final item in content) {
        final text = _extractText(item, decorate: decorate);
        if (text.isNotEmpty) parts.add(text);
      }
      return parts.join('\n');
    }

    if (content is Map<String, dynamic>) {
      if (_isNotDefinitionText(content)) return '';
      final tag = content['tag'];
      final key = _dataContent(content);
      final innerContent = content['content'];

      if (decorate && tag == 'ol' && key == 'glosses') {
        return _numberedGlosses(innerContent);
      }
      if (innerContent != null) {
        final text = _extractText(innerContent, decorate: decorate);
        // Add appropriate formatting based on tag type
        if (decorate && key == 'sense') {
          final style = content['style'];
          final marker = quotedListMarker(
            style is Map ? style['listStyleType'] : null,
          );
          final glosses = oneLine(text);
          return (marker == null || marker.isEmpty)
              ? glosses
              : '$marker $glosses';
        }
        if (decorate && tag == 'li' && key != 'sense-group') {
          return '  ▸ $text'; // small triangle bullet
        }
        return text;
      }
    }

    return '';
  }

  /// `data.content` values of Jitendex and Wiktionary (wty) nodes that are not
  /// the definition: badges, examples, cross-references, notes, forms,
  /// credits. Kept out of plain text (Anki, saved words) and the search
  /// index. None is a JMdict key (glossary, refGlosses, references,
  /// formsTable, notes, sourceLanguages, infoGlossary, antonyms), so JMdict
  /// text stays exactly as it was.
  static const _nonDefinitionKeys = {
    'extra-info',
    'part-of-speech-info',
    'misc-info',
    'field-info',
    'dialect-info',
    'forms',
    'antonym',
    'reference-label',
    'redirect-glossary',
    'backlink',
    'preamble',
    'summary-entry',
    'tags',
    'related-words',
  };

  static const _nonDefinitionPrefixes = [
    'example-sentence',
    'attribution',
    'xref',
    'sense-note',
    'lang-source',
    'info-gloss',
    'graphic',
    'details-entry-',
  ];

  static bool _isNotDefinitionText(Map<String, dynamic> node) {
    final tag = node['tag'];
    if (tag == 'rt' || tag == 'rp' || tag == 'img') return true;
    final key = _dataContent(node);
    return key != null &&
        (_nonDefinitionKeys.contains(key) ||
            _nonDefinitionPrefixes.any(key.startsWith));
  }

  static String? _dataContent(Map<String, dynamic> node) {
    final data = node['data'];
    return data is Map ? data['content']?.toString() : null;
  }

  /// One gloss line out of several: bullets dropped, joined with "; ".
  static String oneLine(String text) => text
      .split('\n')
      .map((line) => line.replaceFirst(_bullet, '').trim())
      .where((line) => line.isNotEmpty)
      .join('; ');

  static final _bullet = RegExp(r'^\s*▸\s*');

  /// Wiktionary's `ol[data-content=glosses]`: "1. gloss", "2. gloss", …
  static String _numberedGlosses(dynamic items) {
    final lines = <String>[];
    for (final item in items is List ? items : [items]) {
      final inner = item is Map<String, dynamic> ? item['content'] : item;
      final text = oneLine(_extractText(inner, decorate: true));
      if (text.isNotEmpty) lines.add('${lines.length + 1}. $text');
    }
    return lines.join('\n');
  }
}
