import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/wanikani/data/models/wanikani_snapshot.dart';

void main() {
  final snapshot = WanikaniSnapshot(
    username: 'crabigator',
    level: 12,
    stages: {'日'.runes.first: 9, '本'.runes.first: 5, '語'.runes.first: 0},
    syncedAt: DateTime.utc(2026, 9, 10, 8, 30),
  );

  group('WanikaniSnapshot', () {
    test('encodes stages keyed by the kanji character', () {
      final json = jsonDecode(snapshot.encode()) as Map<String, dynamic>;
      expect(json['username'], 'crabigator');
      expect(json['level'], 12);
      expect(json['synced_at'], '2026-09-10T08:30:00.000Z');
      expect(json['stages'], {'日': 9, '本': 5, '語': 0});
    });

    test('round-trips through encode/decode', () {
      final decoded = WanikaniSnapshot.decode(snapshot.encode())!;
      expect(decoded.username, snapshot.username);
      expect(decoded.level, snapshot.level);
      expect(decoded.stages, snapshot.stages);
      expect(decoded.syncedAt, snapshot.syncedAt);
    });

    test('knownKanji filters by minimum stage', () {
      expect(snapshot.knownKanji(9), {'日'.runes.first});
      expect(snapshot.knownKanji(5), {'日'.runes.first, '本'.runes.first});
      expect(snapshot.knownKanji(1), {'日'.runes.first, '本'.runes.first});
      expect(snapshot.knownKanji(0), snapshot.stages.keys.toSet());
    });

    test('decode rejects null, garbage and wrong shapes', () {
      expect(WanikaniSnapshot.decode(null), isNull);
      expect(WanikaniSnapshot.decode(''), isNull);
      expect(WanikaniSnapshot.decode('not json'), isNull);
      expect(WanikaniSnapshot.decode('[]'), isNull);
      expect(WanikaniSnapshot.decode('{"username":"x"}'), isNull);
      expect(
        WanikaniSnapshot.decode(
          '{"username":"x","level":"1","synced_at":"2026-01-01T00:00:00Z",'
          '"stages":{}}',
        ),
        isNull,
        reason: 'level must be an int',
      );
      expect(
        WanikaniSnapshot.decode(
          '{"username":"x","level":1,"synced_at":"yesterday","stages":{}}',
        ),
        isNull,
        reason: 'synced_at must parse',
      );
      expect(
        WanikaniSnapshot.decode(
          '{"username":"x","level":1,"synced_at":"2026-01-01T00:00:00Z",'
          '"stages":{"日本":9}}',
        ),
        isNull,
        reason: 'stage keys are single characters',
      );
      expect(
        WanikaniSnapshot.decode(
          '{"username":"x","level":1,"synced_at":"2026-01-01T00:00:00Z",'
          '"stages":{"日":"9"}}',
        ),
        isNull,
        reason: 'stages are ints',
      );
    });

    test('decode accepts an empty stage map', () {
      final decoded = WanikaniSnapshot.decode(
        '{"username":"x","level":1,"synced_at":"2026-01-01T00:00:00Z",'
        '"stages":{}}',
      );
      expect(decoded, isNotNull);
      expect(decoded!.stages, isEmpty);
      expect(decoded.knownKanji(1), isEmpty);
    });
  });
}
