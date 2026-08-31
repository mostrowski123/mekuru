import 'package:mekuru/features/ankidroid/data/models/ankidroid_config.dart';
import 'package:mekuru/features/ankidroid/data/services/ankidroid_service.dart';
import 'package:mekuru/features/ankidroid/presentation/providers/ankidroid_providers.dart';

/// Fake AnkiDroid backend with mutable canned data. Null `fieldList` /
/// `deckList` simulate a failed query, mirroring [AnkidroidService].
class FakeAnkidroidService extends AnkidroidService {
  final List<({int modelId, int deckId, String firstFieldValue})>
  duplicateChecks = [];

  Map<int, String> modelList = {5: 'Basic'};
  List<String>? fieldList = ['Front', 'Back'];
  Map<int, String>? deckList = {1: 'Default', 2: 'Mining'};
  Set<int> duplicateDeckIds = {2};
  Object? addNoteError;
  int? addNoteResult = 42;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<bool> init() async => true;

  @override
  Future<Map<int, String>> getModelList() async => modelList;

  @override
  Future<List<String>?> getFieldList(int modelId) async => fieldList;

  @override
  Future<Map<int, String>?> getDeckList() async => deckList;

  @override
  Future<int?> addNote({
    required int modelId,
    required int deckId,
    required List<String> fields,
    List<String> tags = const ['mekuru'],
  }) async {
    if (addNoteError != null) throw addNoteError!;
    return addNoteResult;
  }

  @override
  Future<bool> hasDuplicateInDeck({
    required int modelId,
    required int deckId,
    required String firstFieldValue,
  }) async {
    duplicateChecks.add((
      modelId: modelId,
      deckId: deckId,
      firstFieldValue: firstFieldValue,
    ));
    return duplicateDeckIds.contains(deckId);
  }

  @override
  void dispose() {}
}

/// Seeds a fixed config and skips persistence so tests need no settings
/// storage backend.
class TestAnkidroidConfigNotifier extends AnkidroidConfigNotifier {
  TestAnkidroidConfigNotifier(this.initial);

  final AnkidroidConfig initial;

  @override
  AnkidroidConfig build() => initial;

  @override
  void setConfig(AnkidroidConfig config) {
    state = config;
  }
}
