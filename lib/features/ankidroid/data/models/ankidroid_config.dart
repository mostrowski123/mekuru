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

  /// The note type's field names in Anki's order, cached from the last
  /// successful getFieldList. [fieldMapping] key order goes stale when the
  /// user renames or reorders fields in AnkiDroid (repairs append at the
  /// end), so first-field derivation must use this instead. Empty on
  /// configs saved before this field existed.
  final List<String> ankiFieldNames;

  /// Default tags to apply to every exported note.
  final List<String> tags;

  /// Address of the AnkiConnect add-on (iOS only), e.g.
  /// `http://192.168.1.20:8765`. Empty until the user enters one.
  final String ankiConnectUrl;

  /// iOS only: export to AnkiMobile on this device (the default) instead of
  /// AnkiConnect.
  final bool useAnkiMobile;

  /// What the user typed for AnkiMobile, whose URL scheme cannot list note
  /// types, decks or fields. Must match the names in AnkiMobile exactly.
  final String ankiMobileNoteType;
  final String ankiMobileDeck;
  final List<String> ankiMobileFields;

  /// iOS only: the inactive backend's selection ([_selection]), swapped back
  /// in by [withUseAnkiMobile] so switching backends loses neither mapping.
  final Map<String, dynamic> parkedSelection;

  const AnkidroidConfig({
    this.modelId,
    this.modelName,
    this.deckId,
    this.deckName,
    this.fieldMapping = const {},
    this.ankiFieldNames = const [],
    this.tags = const ['mekuru'],
    this.ankiConnectUrl = '',
    this.useAnkiMobile = true,
    this.ankiMobileNoteType = '',
    this.ankiMobileDeck = '',
    this.ankiMobileFields = const [],
    this.parkedSelection = const {},
  });

  bool get isConfigured => modelId != null && deckId != null;

  AnkidroidConfig copyWith({
    int? modelId,
    String? modelName,
    int? deckId,
    String? deckName,
    Map<String, String>? fieldMapping,
    List<String>? ankiFieldNames,
    List<String>? tags,
    String? ankiConnectUrl,
    String? ankiMobileNoteType,
    String? ankiMobileDeck,
    List<String>? ankiMobileFields,
  }) {
    return AnkidroidConfig(
      modelId: modelId ?? this.modelId,
      modelName: modelName ?? this.modelName,
      deckId: deckId ?? this.deckId,
      deckName: deckName ?? this.deckName,
      fieldMapping: fieldMapping ?? this.fieldMapping,
      ankiFieldNames: ankiFieldNames ?? this.ankiFieldNames,
      tags: tags ?? this.tags,
      ankiConnectUrl: ankiConnectUrl ?? this.ankiConnectUrl,
      useAnkiMobile: useAnkiMobile,
      ankiMobileNoteType: ankiMobileNoteType ?? this.ankiMobileNoteType,
      ankiMobileDeck: ankiMobileDeck ?? this.ankiMobileDeck,
      ankiMobileFields: ankiMobileFields ?? this.ankiMobileFields,
      parkedSelection: parkedSelection,
    );
  }

  /// Switches the iOS backend: the current selection is parked and the other
  /// backend's parked selection (nothing, the first time) becomes current.
  AnkidroidConfig withUseAnkiMobile(bool value) {
    if (value == useAnkiMobile) return this;
    final parked = AnkidroidConfig.fromJson(parkedSelection);
    return AnkidroidConfig(
      modelId: parked.modelId,
      modelName: parked.modelName,
      deckId: parked.deckId,
      deckName: parked.deckName,
      fieldMapping: parked.fieldMapping,
      ankiFieldNames: parked.ankiFieldNames,
      tags: tags,
      ankiConnectUrl: ankiConnectUrl,
      useAnkiMobile: value,
      ankiMobileNoteType: ankiMobileNoteType,
      ankiMobileDeck: ankiMobileDeck,
      ankiMobileFields: ankiMobileFields,
      parkedSelection: _selection,
    );
  }

  /// The values that belong to one backend: its note type, deck and mapping.
  Map<String, dynamic> get _selection => {
    'modelId': modelId,
    'modelName': modelName,
    'deckId': deckId,
    'deckName': deckName,
    'fieldMapping': fieldMapping,
    'ankiFieldNames': ankiFieldNames,
  };

  Map<String, dynamic> toJson() => {
    ..._selection,
    'tags': tags,
    'ankiConnectUrl': ankiConnectUrl,
    'useAnkiMobile': useAnkiMobile,
    'ankiMobileNoteType': ankiMobileNoteType,
    'ankiMobileDeck': ankiMobileDeck,
    'ankiMobileFields': ankiMobileFields,
    'parkedSelection': parkedSelection,
  };

  factory AnkidroidConfig.fromJson(Map<String, dynamic> json) {
    return AnkidroidConfig(
      modelId: json['modelId'] as int?,
      modelName: json['modelName'] as String?,
      deckId: json['deckId'] as int?,
      deckName: json['deckName'] as String?,
      fieldMapping:
          (json['fieldMapping'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, v as String),
          ) ??
          {},
      ankiFieldNames:
          (json['ankiFieldNames'] as List<dynamic>?)?.cast<String>() ??
          const [],
      tags:
          (json['tags'] as List<dynamic>?)?.cast<String>() ?? const ['mekuru'],
      ankiConnectUrl: json['ankiConnectUrl'] as String? ?? '',
      // Configs saved before the choice existed stay on AnkiConnect when
      // they already carry its address.
      useAnkiMobile:
          json['useAnkiMobile'] as bool? ??
          (json['ankiConnectUrl'] as String? ?? '').isEmpty,
      ankiMobileNoteType: json['ankiMobileNoteType'] as String? ?? '',
      ankiMobileDeck: json['ankiMobileDeck'] as String? ?? '',
      ankiMobileFields:
          (json['ankiMobileFields'] as List<dynamic>?)?.cast<String>() ??
          const [],
      parkedSelection:
          json['parkedSelection'] as Map<String, dynamic>? ?? const {},
    );
  }

  String encode() => jsonEncode(toJson());

  static AnkidroidConfig? decode(String? json) {
    if (json == null) return null;
    try {
      return AnkidroidConfig.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}
