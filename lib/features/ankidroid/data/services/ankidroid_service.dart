import 'package:ankidroid_for_flutter/ankidroid_for_flutter.dart';

/// Wrapper around the ankidroid_for_flutter API.
///
/// Handles permission requests, isolate lifecycle, and all API calls.
/// Methods return null/empty on failure to allow graceful degradation.
class AnkidroidService {
  Ankidroid? _ankidroid;

  /// Whether the service is currently initialized.
  bool get isInitialized => _ankidroid != null;

  /// Request AnkiDroid permission. Returns true if granted.
  Future<bool> requestPermission() async {
    try {
      return await Ankidroid.askForPermission();
    } catch (_) {
      return false;
    }
  }

  /// Initialize the AnkiDroid isolate. Safe to call multiple times.
  Future<bool> init() async {
    if (_ankidroid != null) return true;
    try {
      _ankidroid = await Ankidroid.createAnkiIsolate();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Get list of note models. Returns map of {modelId: modelName}.
  Future<Map<int, String>> getModelList() async {
    if (_ankidroid == null) return {};
    try {
      final result = await _ankidroid!.modelList();
      final value = result.asValue?.value;
      if (value == null) return {};
      // AnkiDroid API returns {modelId (Long): modelName (String)}
      return Map<int, String>.fromEntries(
        value.entries.map(
          (e) => MapEntry(
            (e.key is int) ? e.key as int : int.parse(e.key.toString()),
            e.value.toString(),
          ),
        ),
      );
    } catch (_) {
      return {};
    }
  }

  /// Get field names for a given model ID.
  Future<List<String>> getFieldList(int modelId) async {
    if (_ankidroid == null) return [];
    try {
      final result = await _ankidroid!.getFieldList(modelId);
      final value = result.asValue?.value;
      if (value == null) return [];
      return List<String>.from(value);
    } catch (_) {
      return [];
    }
  }

  /// Get list of decks. Returns map of {deckId: deckName}.
  Future<Map<int, String>> getDeckList() async {
    if (_ankidroid == null) return {};
    try {
      final result = await _ankidroid!.deckList();
      final value = result.asValue?.value;
      if (value == null) return {};
      // AnkiDroid API returns {deckId (Long): deckName (String)}
      return Map<int, String>.fromEntries(
        value.entries.map(
          (e) => MapEntry(
            (e.key is int) ? e.key as int : int.parse(e.key.toString()),
            e.value.toString(),
          ),
        ),
      );
    } catch (_) {
      return {};
    }
  }

  /// Check for duplicate notes by the first field value.
  Future<bool> hasDuplicate(int modelId, String firstFieldValue) async {
    if (_ankidroid == null) return false;
    try {
      final result = await _ankidroid!.findDuplicateNotesWithKey(
        modelId,
        firstFieldValue,
      );
      final value = result.asValue?.value;
      return value != null && value.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Add a note to AnkiDroid. Returns the new note ID, or null on failure.
  Future<int?> addNote({
    required int modelId,
    required int deckId,
    required List<String> fields,
    List<String> tags = const ['mekuru'],
  }) async {
    if (_ankidroid == null) return null;
    try {
      final result = await _ankidroid!.addNote(modelId, deckId, fields, tags);
      return result.asValue?.value;
    } catch (_) {
      return null;
    }
  }

  /// Clean up the isolate.
  void dispose() {
    _ankidroid?.killIsolate();
    _ankidroid = null;
  }
}
