import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mekuru/features/ankidroid/data/services/ankidroid_service.dart';

/// Anki desktop backend (iOS): the AnkiConnect add-on's HTTP JSON API behind
/// the same contract as [AnkidroidService].
///
/// AnkiConnect addresses note types and decks by name while the app stores
/// their ids, so the id → name maps from the last list queries are cached.
class AnkiConnectService implements AnkidroidService {
  AnkiConnectService(this._url, {http.Client? client})
    : _client = client ?? http.Client();

  final String _url;
  final http.Client _client;

  bool _initialized = false;
  Map<int, String> _models = {};
  Map<int, String> _decks = {};

  /// Whether [url] is a usable AnkiConnect address (http/https with a host).
  static bool isValidUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  @override
  bool get isInitialized => _initialized;

  /// AnkiConnect has no permission step; [init] reports whether it answers.
  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<bool> init() async {
    if (_initialized) return true;
    if (!isValidUrl(_url)) return false;
    try {
      final version = await _invoke('version');
      _initialized = version is int && version >= 6;
    } catch (_) {
      _initialized = false;
    }
    return _initialized;
  }

  @override
  Future<Map<int, String>> getModelList() async {
    if (!_initialized) return {};
    try {
      return await _fetchModels();
    } catch (_) {
      return {};
    }
  }

  @override
  Future<List<String>?> getFieldList(int modelId) async {
    if (!_initialized) return null;
    try {
      // Always refreshed: a note type renamed in Anki keeps its id, and a
      // stale name would read as a failed query.
      final modelName = (await _fetchModels())[modelId];
      if (modelName == null) return [];
      return await _fetchFieldNames(modelName);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Map<int, String>?> getDeckList() async {
    if (!_initialized) return null;
    try {
      return await _fetchDecks();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> hasDuplicateInDeck({
    required int modelId,
    required int deckId,
    required String firstFieldValue,
  }) async {
    final value = firstFieldValue.trim();
    if (value.isEmpty) return false;
    try {
      // ponytail: every check while Anki is unreachable waits out the
      // timeout; add a back-off if the lookup sheet's spinner gets annoying.
      if (!await init()) return false;
      final modelName = _models[modelId] ?? (await _fetchModels())[modelId];
      final deckName = _decks[deckId] ?? (await _fetchDecks())[deckId];
      if (modelName == null || deckName == null) return false;
      final fieldNames = await _fetchFieldNames(modelName);
      if (fieldNames.isEmpty) return false;
      final notes = await _invoke('findNotes', {
        'query':
            '${_quote('deck:$deckName')} ${_quote('note:$modelName')} '
            '${_quote('${fieldNames.first}:$value')}',
      });
      return (notes as List).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Unlike the read methods this throws — on a failed request, or with
  /// AnkiConnect's own error — so a failed send stays diagnosable.
  @override
  Future<int?> addNote({
    required int modelId,
    required int deckId,
    required List<String> fields,
    List<String> tags = const ['mekuru'],
  }) async {
    if (!_initialized) return null;
    final modelName = _models[modelId] ?? (await _fetchModels())[modelId];
    final deckName = _decks[deckId] ?? (await _fetchDecks())[deckId];
    if (modelName == null || deckName == null) {
      throw Exception('note type or deck not found');
    }
    final fieldNames = await _fetchFieldNames(modelName);
    final noteId = await _invoke('addNote', {
      'note': {
        'deckName': deckName,
        'modelName': modelName,
        'fields': {
          for (var i = 0; i < fieldNames.length && i < fields.length; i++)
            fieldNames[i]: fields[i],
        },
        'tags': tags,
        // The app runs its own duplicate check, as on Android.
        'options': {'allowDuplicate': true},
      },
    });
    return noteId as int?;
  }

  @override
  void dispose() {
    _initialized = false;
    _client.close();
  }

  Future<Map<int, String>> _fetchModels() async =>
      _models = _invert(await _invoke('modelNamesAndIds'));

  Future<Map<int, String>> _fetchDecks() async =>
      _decks = _invert(await _invoke('deckNamesAndIds'));

  Future<List<String>> _fetchFieldNames(String modelName) async {
    final names = await _invoke('modelFieldNames', {'modelName': modelName});
    return (names as List).cast<String>();
  }

  /// AnkiConnect answers {name: id}; the app keys everything by id.
  static Map<int, String> _invert(Object? namesAndIds) => {
    for (final entry in (namesAndIds as Map<String, dynamic>).entries)
      entry.value as int: entry.key,
  };

  /// Quotes one Anki search term, escaping what would end or alter it.
  static String _quote(String term) =>
      '"${term.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

  /// Runs one AnkiConnect action and returns its `result`. Throws when the
  /// request fails or AnkiConnect reports an error.
  Future<Object?> _invoke(
    String action, [
    Map<String, Object?> params = const {},
  ]) async {
    final Map<String, dynamic> body;
    try {
      final response = await _client
          .post(
            Uri.parse(_url),
            body: jsonEncode({
              'action': action,
              'version': 6,
              'params': params,
            }),
          )
          .timeout(const Duration(seconds: 5));
      // AnkiConnect sends no charset; `response.body` would decode Japanese
      // names as latin1.
      body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (e) {
      // Type only: these messages reach telemetry and the original carries
      // the address.
      throw Exception('AnkiConnect request failed: ${e.runtimeType}');
    }
    final error = body['error'];
    if (error != null) {
      // AnkiConnect appends the deck / note type name after a colon
      // ("deck was not found: …"); keep user text out of telemetry.
      final message = '$error'.split(':').first;
      throw Exception('AnkiConnect: $message');
    }
    return body['result'];
  }
}
