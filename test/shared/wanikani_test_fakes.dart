import 'dart:async';

import 'package:mekuru/features/wanikani/data/models/wanikani_snapshot.dart';
import 'package:mekuru/features/wanikani/data/services/wanikani_api_client.dart';
import 'package:mekuru/features/wanikani/data/services/wanikani_storage.dart';

int rune(String kanji) => kanji.runes.single;

/// Scripted API client: answers with [user] and [stages], or throws [error].
/// [gate] (when set) holds every call until completed, for overlap tests.
class FakeWanikaniApiClient extends WanikaniApiClient {
  WanikaniUser user = const WanikaniUser(username: 'crabigator', level: 5);
  Map<int, int> stages = {rune('日'): 9, rune('本'): 5};
  Map<int, int> subjectRunes = {440: rune('日'), 441: rune('本')};
  Object? error;
  Completer<void>? gate;
  int userCalls = 0;
  int stagesCalls = 0;
  final tokens = <String>[];
  final receivedSubjectRunes = <Map<int, int>>[];

  @override
  Future<WanikaniUser> fetchUser(String token) async {
    userCalls++;
    tokens.add(token);
    await gate?.future;
    if (error != null) throw error!;
    return user;
  }

  @override
  Future<KanjiStages> fetchKanjiStages(
    String token, {
    Map<int, int> subjectRunes = const {},
  }) async {
    stagesCalls++;
    receivedSubjectRunes.add(subjectRunes);
    await gate?.future;
    if (error != null) throw error!;
    return (stages: Map.of(stages), subjectRunes: Map.of(this.subjectRunes));
  }
}

/// In-memory storage: what the secure store and prefs would hold.
class FakeWanikaniStorage extends WanikaniStorage {
  FakeWanikaniStorage({this.token, this.snapshot});

  String? token;
  WanikaniSnapshot? snapshot;
  int tokenSaves = 0;
  int snapshotSaves = 0;

  @override
  Future<String?> loadToken() async => token;

  @override
  Future<void> saveToken(String value) async {
    tokenSaves++;
    token = value.trim().isEmpty ? null : value.trim();
  }

  @override
  Future<void> clearToken() async => token = null;

  @override
  Future<WanikaniSnapshot?> loadSnapshot() async => snapshot;

  @override
  Future<void> saveSnapshot(WanikaniSnapshot value) async {
    snapshotSaves++;
    snapshot = value;
  }

  @override
  Future<void> clearSnapshot() async => snapshot = null;
}

WanikaniSnapshot snapshotAt(DateTime syncedAt, {Map<int, int>? stages}) =>
    WanikaniSnapshot(
      username: 'crabigator',
      level: 5,
      stages: stages ?? {rune('日'): 9, rune('本'): 5},
      subjectRunes: {440: rune('日'), 441: rune('本')},
      syncedAt: syncedAt,
    );
