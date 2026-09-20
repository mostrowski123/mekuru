import 'package:mekuru/features/ankidroid/data/services/ankidroid_service.dart';
import 'package:url_launcher/url_launcher.dart';

/// AnkiMobile backend (iOS): the Anki app on this device, driven through its
/// `anki://x-callback-url/addnote` URL scheme behind the same contract as
/// [AnkidroidService].
///
/// The scheme is add-only — nothing can be listed or queried — so the user
/// types the note type, deck and field names, and they are presented as one
/// synthetic note type and one synthetic deck.
class AnkiMobileService implements AnkidroidService {
  AnkiMobileService({
    required this.noteType,
    required this.deck,
    required this.fieldNames,
    Future<bool> Function(Uri url)? canLaunch,
    Future<bool> Function(Uri url)? launch,
  }) : _canLaunch = canLaunch ?? canLaunchUrl,
       _launch =
           launch ??
           ((url) => launchUrl(url, mode: LaunchMode.externalApplication));

  /// Id of the synthetic note type and deck (and of every "added" note).
  /// Negative, so it can never collide with a real Anki id.
  static const syntheticId = -1;

  final String noteType;
  final String deck;
  final List<String> fieldNames;
  final Future<bool> Function(Uri url) _canLaunch;
  final Future<bool> Function(Uri url) _launch;

  bool _initialized = false;

  /// The `addnote` URL for one note. Pure, so the encoding is testable.
  static Uri buildAddNoteUrl({
    required String noteType,
    required String deck,
    required List<String> fieldNames,
    required List<String> fields,
    List<String> tags = const [],
  }) {
    final params = {
      'type': noteType,
      'deck': deck,
      for (var i = 0; i < fieldNames.length && i < fields.length; i++)
        if (fields[i].isNotEmpty) 'fld${fieldNames[i]}': fields[i],
      if (tags.isNotEmpty) 'tags': tags.join(' '),
      // Brings the user back here once AnkiMobile has added the note. No
      // `dupes=1`: the app cannot check duplicates, so AnkiMobile refuses
      // them with its own message.
      'x-success': 'mekuru://anki',
    };
    // Not Uri(queryParameters:): that writes spaces as '+', which iOS URL
    // parsing keeps as a literal plus.
    final query = params.entries
        .map(
          (e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
        )
        .join('&');
    return Uri.parse('anki://x-callback-url/addnote?$query');
  }

  @override
  bool get isInitialized => _initialized;

  /// A URL scheme has no permission step.
  @override
  Future<bool> requestPermission() async => true;

  /// True when AnkiMobile is installed and all three names are configured.
  @override
  Future<bool> init() async {
    if (_initialized) return true;
    if (noteType.isEmpty || deck.isEmpty || fieldNames.isEmpty) return false;
    try {
      _initialized = await _canLaunch(Uri.parse('anki://x-callback-url'));
    } catch (_) {
      _initialized = false;
    }
    return _initialized;
  }

  @override
  Future<Map<int, String>> getModelList() async =>
      _initialized ? {syntheticId: noteType} : {};

  @override
  Future<List<String>?> getFieldList(int modelId) async {
    if (!_initialized) return null;
    return modelId == syntheticId ? fieldNames : [];
  }

  @override
  Future<Map<int, String>?> getDeckList() async =>
      _initialized ? {syntheticId: deck} : null;

  /// AnkiMobile cannot be queried; it rejects duplicates itself on add.
  @override
  Future<bool> hasDuplicateInDeck({
    required int modelId,
    required int deckId,
    required String firstFieldValue,
  }) async => false;

  /// Throws when AnkiMobile is missing or the launch fails, so a failed send
  /// stays diagnosable.
  ///
  // ponytail: a successful launch is all the scheme reports, so a note that
  // AnkiMobile then refuses (duplicate, misspelled name) still counts as
  // sent. Handle the mekuru://anki callback (plus x-error) if that matters.
  @override
  Future<int?> addNote({
    required int modelId,
    required int deckId,
    required List<String> fields,
    List<String> tags = const ['mekuru'],
  }) async {
    if (!await init()) {
      throw Exception('AnkiMobile not installed or not configured');
    }
    final bool launched;
    try {
      launched = await _launch(
        buildAddNoteUrl(
          noteType: noteType,
          deck: deck,
          fieldNames: fieldNames,
          fields: fields,
          tags: tags,
        ),
      );
    } catch (e) {
      // Type only: these messages reach telemetry and the original can carry
      // the URL, which is user text.
      throw Exception('AnkiMobile launch failed: ${e.runtimeType}');
    }
    if (!launched) throw Exception('AnkiMobile launch failed');
    return syntheticId;
  }

  @override
  void dispose() {
    _initialized = false;
  }
}
