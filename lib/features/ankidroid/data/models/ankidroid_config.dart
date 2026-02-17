import 'dart:convert';

/// Persisted configuration for AnkiDroid integration.
///
/// Stored as a single JSON string in SharedPreferences.
class AnkidroidConfig {
  final int? modelId;
  final String? modelName;
  final int? deckId;
  final String? deckName;

  /// Mapping from Anki field name → app data source key.
  ///
  /// App data source keys: 'expression', 'reading', 'glossary',
  /// 'sentence_context', 'frequency', 'dictionary_name', 'pitch_accent',
  /// 'empty'.
  final Map<String, String> fieldMapping;

  /// Default tags to apply to every exported note.
  final List<String> tags;

  const AnkidroidConfig({
    this.modelId,
    this.modelName,
    this.deckId,
    this.deckName,
    this.fieldMapping = const {},
    this.tags = const ['mekuru'],
  });

  bool get isConfigured => modelId != null && deckId != null;

  AnkidroidConfig copyWith({
    int? modelId,
    String? modelName,
    int? deckId,
    String? deckName,
    Map<String, String>? fieldMapping,
    List<String>? tags,
  }) {
    return AnkidroidConfig(
      modelId: modelId ?? this.modelId,
      modelName: modelName ?? this.modelName,
      deckId: deckId ?? this.deckId,
      deckName: deckName ?? this.deckName,
      fieldMapping: fieldMapping ?? this.fieldMapping,
      tags: tags ?? this.tags,
    );
  }

  Map<String, dynamic> toJson() => {
        'modelId': modelId,
        'modelName': modelName,
        'deckId': deckId,
        'deckName': deckName,
        'fieldMapping': fieldMapping,
        'tags': tags,
      };

  factory AnkidroidConfig.fromJson(Map<String, dynamic> json) {
    return AnkidroidConfig(
      modelId: json['modelId'] as int?,
      modelName: json['modelName'] as String?,
      deckId: json['deckId'] as int?,
      deckName: json['deckName'] as String?,
      fieldMapping: (json['fieldMapping'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as String)) ??
          {},
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ??
          const ['mekuru'],
    );
  }

  String encode() => jsonEncode(toJson());

  static AnkidroidConfig? decode(String? json) {
    if (json == null) return null;
    try {
      return AnkidroidConfig.fromJson(
        jsonDecode(json) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }
}
