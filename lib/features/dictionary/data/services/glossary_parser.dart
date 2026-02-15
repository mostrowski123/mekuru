import 'dart:convert';

/// Utility for parsing glossary entries stored as JSON strings.
///
/// Glossary items can be either plain strings or JSON-encoded structured-content
/// objects (e.g. from Yomitan dictionaries like NEW斎藤和英大辞典).
/// This parser extracts human-readable text from both formats.
class GlossaryParser {
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
      return [glossariesJson];
    }
  }

  /// Convert a single glossary item into readable text.
  static String _itemToReadableText(dynamic item) {
    if (item is String) {
      // Could be a plain string OR a JSON-encoded structured-content object.
      return _tryParseStructuredContent(item);
    }
    // Shouldn't happen for DB-stored values, but handle gracefully.
    return item.toString();
  }

  /// Try to parse a string as a structured-content JSON object.
  /// If it's a structured-content object, extract readable text.
  /// Otherwise return the string as-is.
  static String _tryParseStructuredContent(String value) {
    if (!value.startsWith('{')) return value;

    try {
      final parsed = jsonDecode(value);
      if (parsed is Map<String, dynamic> &&
          parsed['type'] == 'structured-content') {
        final text = _extractText(parsed['content']);
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
  static String _extractText(dynamic content) {
    if (content == null) return '';
    if (content is String) return content;
    if (content is num || content is bool) return content.toString();

    if (content is List) {
      final parts = <String>[];
      for (final item in content) {
        final text = _extractText(item);
        if (text.isNotEmpty) parts.add(text);
      }
      return parts.join('\n');
    }

    if (content is Map<String, dynamic>) {
      final tag = content['tag'];
      final innerContent = content['content'];

      if (innerContent != null) {
        final text = _extractText(innerContent);
        // Add appropriate formatting based on tag type
        if (tag == 'li') {
          return '  \u25b8 $text'; // small triangle bullet
        }
        return text;
      }
    }

    return '';
  }
}
