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
/// Read methods return null/empty on failure to allow graceful degradation;
/// [addNote] rethrows so send failures stay diagnosable.
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

  /// Get field names for a given model ID. Returns an empty list when the
  /// model no longer exists in AnkiDroid, or null when the query itself
  /// failed — callers must not present a failed query as a deleted model.
  Future<List<String>?> getFieldList(int modelId) async {
    if (!_initialized) return null;
    try {
      final result = await _nativeChannel.invokeListMethod<String>(
        'getFieldList',
        {'modelId': modelId},
      );
      // The native AddContentApi returns null for an unknown model.
      return result ?? [];
    } catch (_) {
      return null;
    }
  }

  /// Get list of decks as {deckId: deckName}, or null when the query
  /// failed. AnkiDroid always has at least one deck, so a native null is a
  /// failure, never an empty collection.
  Future<Map<int, String>?> getDeckList() async {
    if (!_initialized) return null;
    try {
      return await _nativeChannel.invokeMapMethod<int, String>('getDeckList');
    } catch (_) {
      return null;
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

  /// Add a note to AnkiDroid. Returns the new note ID, or null when
  /// AnkiDroid rejects the insert without an error. Unlike the read methods,
  /// this rethrows channel errors so callers can report the actual cause of
  /// a failed send.
  Future<int?> addNote({
    required int modelId,
    required int deckId,
    required List<String> fields,
    List<String> tags = const ['mekuru'],
  }) async {
    if (!_initialized) return null;
    return _nativeChannel.invokeMethod<int>('addNote', {
      'modelId': modelId,
      'deckId': deckId,
      'fields': fields,
      'tags': tags,
    });
  }

  /// Reset initialization state.
  void dispose() {
    _initialized = false;
  }
}
