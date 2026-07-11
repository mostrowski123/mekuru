import 'package:ankidroid_for_flutter/ankidroid_for_flutter.dart';
import 'package:flutter/services.dart';

/// Wrapper around the AnkiDroid AddContentApi.
///
/// All content-provider operations go through the app's own
/// `mekuru/ankidroid_native` channel, which runs them on a background
/// thread — AnkiDroid's provider can block for seconds while its process
/// cold-starts, and touching it on the Android main thread ANRs the app.
/// The `ankidroid_for_flutter` plugin is only used for the permission
/// prompt, which never touches the provider.
///
/// Methods return null/empty on failure to allow graceful degradation.
class AnkidroidService {
  static const MethodChannel _nativeChannel = MethodChannel(
    'mekuru/ankidroid_native',
  );

  bool _initialized = false;

  /// Whether the service is currently initialized.
  bool get isInitialized => _initialized;

  /// Request AnkiDroid permission. Returns true if granted.
  Future<bool> requestPermission() async {
    try {
      return await Ankidroid.askForPermission();
    } catch (_) {
      return false;
    }
  }

  /// Check that the AnkiDroid API is available. Safe to call multiple times.
  Future<bool> init() async {
    if (_initialized) return true;
    try {
      final available = await _nativeChannel.invokeMethod<bool>(
        'isApiAvailable',
      );
      _initialized = available ?? false;
    } catch (_) {
      _initialized = false;
    }
    return _initialized;
  }

  /// Get list of note models. Returns map of {modelId: modelName}.
  Future<Map<int, String>> getModelList() async {
    if (!_initialized) return {};
    try {
      final result = await _nativeChannel.invokeMapMethod<int, String>(
        'getModelList',
      );
      return result ?? {};
    } catch (_) {
      return {};
    }
  }

  /// Get field names for a given model ID.
  Future<List<String>> getFieldList(int modelId) async {
    if (!_initialized) return [];
    try {
      final result = await _nativeChannel.invokeListMethod<String>(
        'getFieldList',
        {'modelId': modelId},
      );
      return result ?? [];
    } catch (_) {
      return [];
    }
  }

  /// Get list of decks. Returns map of {deckId: deckName}.
  Future<Map<int, String>> getDeckList() async {
    if (!_initialized) return {};
    try {
      final result = await _nativeChannel.invokeMapMethod<int, String>(
        'getDeckList',
      );
      return result ?? {};
    } catch (_) {
      return {};
    }
  }

  /// Check whether a duplicate note already exists in a specific deck.
  Future<bool> hasDuplicateInDeck({
    required int modelId,
    required int deckId,
    required String firstFieldValue,
  }) async {
    final normalizedValue = firstFieldValue.trim();
    if (normalizedValue.isEmpty) return false;

    try {
      final result = await _nativeChannel.invokeMethod<bool>(
        'hasDuplicateInDeck',
        {
          'modelId': modelId,
          'deckId': deckId,
          'firstFieldValue': normalizedValue,
        },
      );
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
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
    if (!_initialized) return null;
    try {
      return await _nativeChannel.invokeMethod<int>('addNote', {
        'modelId': modelId,
        'deckId': deckId,
        'fields': fields,
        'tags': tags,
      });
    } catch (_) {
      return null;
    }
  }

  /// Reset initialization state.
  void dispose() {
    _initialized = false;
  }
}
