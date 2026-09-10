import 'dart:convert';

/// The WaniKani account fields Mekuru shows: who is linked and how far along.
class WanikaniUser {
  final String username;
  final int level;

  const WanikaniUser({required this.username, required this.level});
}

/// Failure of a WaniKani API call. [code] is what telemetry and the UI key
/// off: `token_invalid` (401), `rate_limited` (429), `network` (unreachable
/// or timed out), `http` (any other non-2xx), `malformed` (unexpected JSON
/// shape — a bug, not a user condition).
class WanikaniException implements Exception {
  static const tokenInvalid = 'token_invalid';
  static const rateLimited = 'rate_limited';
  static const network = 'network';
  static const http = 'http';
  static const malformed = 'malformed';

  final String code;
  final int statusCode;
  final String message;

  const WanikaniException(this.code, {this.statusCode = 0, this.message = ''});

  @override
  String toString() => 'WanikaniException($code, $statusCode): $message';
}

/// Everything a sync leaves behind: the per-kanji SRS stage map (rune →
/// stage 0..9), the kanji subject catalogue (subject id → rune, static on
/// WaniKani's side and cached so refreshes skip re-downloading it), the
/// account fields and the sync time. Persisted as one JSON string; the API
/// token is deliberately NOT part of it so the snapshot can be backed up
/// while the secret stays in secure storage.
class WanikaniSnapshot {
  final String username;
  final int level;
  final Map<int, int> stages;
  final Map<int, int> subjectRunes;
  final DateTime syncedAt;

  const WanikaniSnapshot({
    required this.username,
    required this.level,
    required this.stages,
    this.subjectRunes = const {},
    required this.syncedAt,
  });

  /// Kanji whose SRS stage has reached [minStage].
  Set<int> knownKanji(int minStage) => {
    for (final entry in stages.entries)
      if (entry.value >= minStage) entry.key,
  };

  Map<String, Object?> toJson() => {
    'username': username,
    'level': level,
    'synced_at': syncedAt.toUtc().toIso8601String(),
    'stages': {
      for (final entry in stages.entries)
        String.fromCharCode(entry.key): entry.value,
    },
    'subjects': {
      for (final entry in subjectRunes.entries)
        '${entry.key}': String.fromCharCode(entry.value),
    },
  };

  String encode() => jsonEncode(toJson());

  /// Null for anything that is not a well-formed snapshot (older or
  /// corrupted values), so a bad preference reads as "never synced".
  static WanikaniSnapshot? decode(String? raw) {
    if (raw == null) return null;
    final Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (json is! Map) return null;
    final username = json['username'];
    final level = json['level'];
    final syncedAt = json['synced_at'];
    final rawStages = json['stages'];
    // Absent in snapshots written before the catalogue was cached; the
    // next sync simply re-downloads it.
    final rawSubjects = json['subjects'] ?? const {};
    if (username is! String ||
        level is! int ||
        syncedAt is! String ||
        rawStages is! Map ||
        rawSubjects is! Map) {
      return null;
    }
    final parsedSyncedAt = DateTime.tryParse(syncedAt);
    if (parsedSyncedAt == null) return null;
    final stages = <int, int>{};
    for (final entry in rawStages.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String || key.runes.length != 1 || value is! int) {
        return null;
      }
      stages[key.runes.first] = value;
    }
    final subjectRunes = <int, int>{};
    for (final entry in rawSubjects.entries) {
      final id = int.tryParse('${entry.key}');
      final value = entry.value;
      if (id == null || value is! String || value.runes.length != 1) {
        return null;
      }
      subjectRunes[id] = value.runes.first;
    }
    return WanikaniSnapshot(
      username: username,
      level: level,
      stages: stages,
      subjectRunes: subjectRunes,
      syncedAt: parsedSyncedAt,
    );
  }
}
