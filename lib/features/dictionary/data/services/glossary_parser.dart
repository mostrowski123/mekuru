import 'dart:convert';

/// Utility for parsing glossary entries stored as JSON strings.
///
/// Glossary items can be either plain strings or JSON-encoded structured-content
/// objects (e.g. from Yomitan dictionaries like NEW斎藤和英大辞典).
/// This parser extracts human-readable text from both formats.
class GlossaryParser {
  /// Shown instead of raw JSON when a stored glossary cannot be decoded
  /// (e.g. truncated by a partial write). Glossary content itself is not
  /// localized, so a plain-English constant is consistent.
  static const unreadableDefinitionPlaceholder = '(unreadable definition)';

  /// Parse a glossaries JSON string into a list of human-readable definitions.
  ///
  /// The [glossariesJson] is a JSON-encoded list where each element is either:
  /// - A plain string definition (returned as-is)
  /// - A JSON-encoded structured-content object (text is extracted recursively)
  static List<String> parse(String glossariesJson) {
    try {
      final List<dynamic> jsonList = jsonDecode(glossariesJson);
      return jsonList.map((item) => _itemToReadableText(item)).toList();
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
  /// plain string or a JSON-encoded structured-content object), one gloss
  /// per line, without display decorations.
  ///
  /// Stored in dictionary_entries.search_text and tokenized by the
  /// English-search FTS index. The line structure matters — the query side
  /// detects "the query is exactly one of this entry's glosses" via
  /// newline-bounded matching.
  static String searchTextFromItems(List<String> items) {
    final lines = <String>[];
    for (final item in items) {
      final text = _tryParseStructuredContent(item, decorate: false);
      for (var line in text.split('\n')) {
        line = line.trim();
        if (line.isNotEmpty) {
          lines.add(line.toLowerCase());
        }
      }
    }
    return lines.join('\n');
  }

  /// [searchTextFromItems] for a stored glossaries JSON string.
  ///
  /// Undecodable JSON yields an empty string — a display placeholder is
  /// useful on screen but would only pollute the search index.
  static String searchText(String glossariesJson) {
    try {
      final List<dynamic> jsonList = jsonDecode(glossariesJson);
      return searchTextFromItems([
        for (final item in jsonList) item is String ? item : item.toString(),
      ]);
    } catch (_) {
      final trimmed = glossariesJson.trim();
      if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
        return '';
      }
      return searchTextFromItems([glossariesJson]);
    }
  }

  /// Convert a single glossary item into readable text.
  static String _itemToReadableText(dynamic item) {
    if (item is String) {
      // Could be a plain string OR a JSON-encoded structured-content object.
      return _tryParseStructuredContent(item, decorate: true);
    }
    // Shouldn't happen for DB-stored values, but handle gracefully.
    return item.toString();
  }

  /// Try to parse a string as a structured-content JSON object.
  /// If it's a structured-content object, extract readable text.
  /// Otherwise return the string as-is.
  static String _tryParseStructuredContent(
    String value, {
    required bool decorate,
  }) {
    if (!value.startsWith('{')) return value;

    try {
      final parsed = jsonDecode(value);
      if (parsed is Map<String, dynamic> &&
          parsed['type'] == 'structured-content') {
        final text = _extractText(parsed['content'], decorate: decorate);
        return text.isNotEmpty ? text : value;
      }
      // JSON object but not structured-content — return as-is
      return value;
    } catch (_) {
      return value;
    }
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
      final tag = content['tag'];
      final innerContent = content['content'];

      if (innerContent != null) {
        final text = _extractText(innerContent, decorate: decorate);
        // Add appropriate formatting based on tag type
        if (decorate && tag == 'li') {
          return '  ▸ $text'; // small triangle bullet
        }
        return text;
      }
    }

    return '';
  }
}
