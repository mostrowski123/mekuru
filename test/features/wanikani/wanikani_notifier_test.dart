import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/features/wanikani/data/models/wanikani_snapshot.dart';
import 'package:mekuru/features/wanikani/presentation/providers/wanikani_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'wanikani_test_fakes.dart';

void main() {
  final now = DateTime.utc(2026, 9, 10, 12);
  late FakeWanikaniApiClient client;
  late FakeWanikaniStorage storage;
  late DateTime clock;
  late List<String> events;
  late List<String> warnings;

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        wanikaniApiClientProvider.overrideWithValue(client),
        wanikaniStorageProvider.overrideWithValue(storage),
        wanikaniClockProvider.overrideWithValue(() => clock),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    client = FakeWanikaniApiClient();
    storage = FakeWanikaniStorage();
    clock = now;
    events = [];
    warnings = [];
    usageLogSinkOverride = (message, attributes, {required isWarning}) {
      (isWarning ? warnings : events).add(message);
    };
  });

  tearDown(() {
    usageLogSinkOverride = null;
  });

  group('loadPersistedSettings', () {
    test('restores a linked account with its snapshot', () async {
      storage
        ..token = 'tok'
        ..snapshot = snapshotAt(now);
      final container = makeContainer();
      await container.read(wanikaniProvider.notifier).loadPersistedSettings();

      final state = container.read(wanikaniProvider);
      expect(state.linked, isTrue);
      expect(state.hasKanji, isTrue);
      expect(state.syncing, isFalse);
    });

    test('a snapshot without a token is restored but not linked', () async {
      storage.snapshot = snapshotAt(now);
      final container = makeContainer();
      await container.read(wanikaniProvider.notifier).loadPersistedSettings();

      final state = container.read(wanikaniProvider);
      expect(state.linked, isFalse);
      expect(state.hasKanji, isTrue);
    });

    test('nothing stored means unlinked and empty', () async {
      final container = makeContainer();
      await container.read(wanikaniProvider.notifier).loadPersistedSettings();

      final state = container.read(wanikaniProvider);
      expect(state.linked, isFalse);
      expect(state.snapshot, isNull);
      expect(state.stages, isEmpty);
    });

    test('runs once', () async {
      storage.token = 'tok';
      final container = makeContainer();
      final notifier = container.read(wanikaniProvider.notifier);
      await notifier.loadPersistedSettings();
      storage.token = null;
      await notifier.loadPersistedSettings();
      expect(container.read(wanikaniProvider).linked, isTrue);
    });
  });

  group('link', () {
    test('validates, syncs, then persists token and snapshot', () async {
      final container = makeContainer();
      await container.read(wanikaniProvider.notifier).link('  tok-1  ');

      expect(client.tokens, ['tok-1']);
      expect(storage.token, 'tok-1');
      expect(storage.snapshot!.username, 'crabigator');
      expect(storage.snapshot!.syncedAt, now);
      final state = container.read(wanikaniProvider);
      expect(state.linked, isTrue);
      expect(state.stages, {rune('日'): 9, rune('本'): 5});
      expect(state.syncing, isFalse);
      expect(events, ['wanikani.synced', 'wanikani.linked']);
      expect(warnings, isEmpty);
    });

    test('a rejected token writes nothing and keeps the old link', () async {
      storage
        ..token = 'old'
        ..snapshot = snapshotAt(now.subtract(const Duration(days: 1)));
      final container = makeContainer();
      final notifier = container.read(wanikaniProvider.notifier);
      await notifier.loadPersistedSettings();
      client.error = const WanikaniException(
        WanikaniException.tokenInvalid,
        statusCode: 401,
      );

      await expectLater(
        () => notifier.link('bad'),
        throwsA(
          isA<WanikaniException>().having(
            (e) => e.code,
            'code',
            WanikaniException.tokenInvalid,
          ),
        ),
      );

      expect(storage.token, 'old');
      expect(storage.tokenSaves, 0);
      expect(storage.snapshotSaves, 0);
      final state = container.read(wanikaniProvider);
      expect(state.linked, isTrue);
      expect(state.snapshot!.syncedAt, now.subtract(const Duration(days: 1)));
      expect(state.syncing, isFalse);
      expect(events, isEmpty);
      expect(warnings, ['wanikani.synced']);
    });

    test('a blank token is rejected without a request', () async {
      final container = makeContainer();
      await expectLater(
        () => container.read(wanikaniProvider.notifier).link('   '),
        throwsA(isA<WanikaniException>()),
      );
      expect(client.userCalls, 0);
    });

    test('waits for an in-flight sync before linking', () async {
      storage
        ..token = 'old'
        ..snapshot = snapshotAt(now.subtract(const Duration(days: 1)));
      final container = makeContainer();
      final notifier = container.read(wanikaniProvider.notifier);
      await notifier.loadPersistedSettings();

      client.gate = Completer<void>();
      final background = notifier.refreshIfDue(trigger: 'startup');
      var linked = false;
      final link = notifier.link('new').then((_) => linked = true);
      await Future<void>.delayed(Duration.zero);
      expect(linked, isFalse);
      expect(client.tokens, ['old']);

      client.gate!.complete();
      await background;
      await link;
      expect(client.tokens, ['old', 'new']);
      expect(storage.token, 'new');
    });
  });

  group('unlink', () {
    test('clears token, snapshot and state', () async {
      storage
        ..token = 'tok'
        ..snapshot = snapshotAt(now);
      final container = makeContainer();
      final notifier = container.read(wanikaniProvider.notifier);
      await notifier.loadPersistedSettings();

      await notifier.unlink();

      expect(storage.token, isNull);
      expect(storage.snapshot, isNull);
      final state = container.read(wanikaniProvider);
      expect(state.linked, isFalse);
      expect(state.snapshot, isNull);
      expect(events, ['wanikani.unlinked']);
    });
  });

  group('refreshIfDue', () {
    test('does nothing when unlinked, even with a restored snapshot', () async {
      storage.snapshot = snapshotAt(now.subtract(const Duration(days: 3)));
      final container = makeContainer();
      final notifier = container.read(wanikaniProvider.notifier);
      await notifier.loadPersistedSettings();

      await notifier.refreshIfDue(trigger: 'startup');
      expect(client.userCalls, 0);
    });

    test('skips a fresh snapshot', () async {
      storage
        ..token = 'tok'
        ..snapshot = snapshotAt(now.subtract(const Duration(minutes: 59)));
      final container = makeContainer();
      final notifier = container.read(wanikaniProvider.notifier);
      await notifier.loadPersistedSettings();

      await notifier.refreshIfDue(trigger: 'startup');
      expect(client.userCalls, 0);
    });

    test('re-syncs a stale snapshot and records the trigger', () async {
      storage
        ..token = 'tok'
        ..snapshot = snapshotAt(
          now.subtract(const Duration(hours: 2)),
          stages: {rune('日'): 1},
        );
      final container = makeContainer();
      final notifier = container.read(wanikaniProvider.notifier);
      await notifier.loadPersistedSettings();

      Map<String, Object?>? syncedAttrs;
      usageLogSinkOverride = (message, attributes, {required isWarning}) {
        if (message == 'wanikani.synced') syncedAttrs = attributes;
      };
      await notifier.refreshIfDue(trigger: 'resume');

      expect(client.userCalls, 1);
      expect(client.tokens, ['tok']);
      final state = container.read(wanikaniProvider);
      expect(state.stages, {rune('日'): 9, rune('本'): 5});
      expect(state.snapshot!.syncedAt, now);
      expect(storage.snapshot!.syncedAt, now);
      expect(syncedAttrs, isNotNull);
      expect(syncedAttrs!.keys, containsAll(['trigger', 'kanji_count']));
    });

    test('syncs when linked without any snapshot', () async {
      storage.token = 'tok';
      final container = makeContainer();
      final notifier = container.read(wanikaniProvider.notifier);
      await notifier.loadPersistedSettings();

      await notifier.refreshIfDue(trigger: 'startup');
      expect(client.userCalls, 1);
      expect(container.read(wanikaniProvider).hasKanji, isTrue);
    });

    test('swallows failures and leaves the old snapshot', () async {
      final old = snapshotAt(now.subtract(const Duration(days: 1)));
      storage
        ..token = 'tok'
        ..snapshot = old;
      client.error = const WanikaniException(WanikaniException.network);
      final container = makeContainer();
      final notifier = container.read(wanikaniProvider.notifier);
      await notifier.loadPersistedSettings();

      await notifier.refreshIfDue(trigger: 'startup');

      final state = container.read(wanikaniProvider);
      expect(state.snapshot, same(old));
      expect(state.linked, isTrue);
      expect(state.syncing, isFalse);
      expect(warnings, ['wanikani.synced']);
    });

    test('a token that vanished from secure storage unlinks', () async {
      storage.token = 'tok';
      final container = makeContainer();
      final notifier = container.read(wanikaniProvider.notifier);
      await notifier.loadPersistedSettings();
      storage.token = null;

      await notifier.refreshIfDue(trigger: 'startup');
      expect(client.userCalls, 0);
      expect(container.read(wanikaniProvider).linked, isFalse);
    });
  });

  group('syncNow', () {
    test('rethrows so the UI can show the error', () async {
      storage.token = 'tok';
      client.error = const WanikaniException(
        WanikaniException.rateLimited,
        statusCode: 429,
      );
      final container = makeContainer();
      final notifier = container.read(wanikaniProvider.notifier);
      await notifier.loadPersistedSettings();

      await expectLater(
        notifier.syncNow,
        throwsA(
          isA<WanikaniException>().having(
            (e) => e.code,
            'code',
            WanikaniException.rateLimited,
          ),
        ),
      );
      expect(container.read(wanikaniProvider).syncing, isFalse);
    });

    test('ignores the staleness gate', () async {
      storage
        ..token = 'tok'
        ..snapshot = snapshotAt(now);
      final container = makeContainer();
      final notifier = container.read(wanikaniProvider.notifier);
      await notifier.loadPersistedSettings();

      await notifier.syncNow();
      expect(client.userCalls, 1);
    });

    test('overlapping calls share one round-trip', () async {
      storage.token = 'tok';
      final container = makeContainer();
      final notifier = container.read(wanikaniProvider.notifier);
      await notifier.loadPersistedSettings();

      client.gate = Completer<void>();
      final first = notifier.syncNow();
      final second = notifier.syncNow();
      await Future<void>.delayed(Duration.zero);
      expect(container.read(wanikaniProvider).syncing, isTrue);
      client.gate!.complete();
      await Future.wait([first, second]);

      expect(client.userCalls, 1);
      expect(client.stagesCalls, 1);
      expect(container.read(wanikaniProvider).syncing, isFalse);
    });

    test('a shared failure reaches the manual caller only', () async {
      storage.token = 'tok';
      client.error = const WanikaniException(WanikaniException.network);
      final container = makeContainer();
      final notifier = container.read(wanikaniProvider.notifier);
      await notifier.loadPersistedSettings();

      client.gate = Completer<void>();
      final silent = notifier.refreshIfDue(trigger: 'startup');
      final manual = notifier.syncNow();
      client.gate!.complete();

      await silent;
      await expectLater(() => manual, throwsA(isA<WanikaniException>()));
      expect(client.userCalls, 1);
    });

    test('unexpected errors are reported as bugs', () async {
      storage.token = 'tok';
      client.error = StateError('boom');
      final container = makeContainer();
      final notifier = container.read(wanikaniProvider.notifier);
      await notifier.loadPersistedSettings();

      await expectLater(notifier.syncNow, throwsStateError);
      expect(warnings, ['wanikani.synced']);
    });
  });

  group('wanikaniKnownKanjiProvider', () {
    test('is empty without a snapshot', () {
      final container = makeContainer();
      expect(container.read(wanikaniKnownKanjiProvider), isEmpty);
    });

    test('filters by the reader threshold and follows changes', () async {
      storage
        ..token = 'tok'
        ..snapshot = snapshotAt(
          now,
          stages: {rune('日'): 9, rune('本'): 5, rune('語'): 1},
        );
      final container = makeContainer();
      await container.read(wanikaniProvider.notifier).loadPersistedSettings();

      expect(container.read(wanikaniKnownKanjiProvider), {rune('日')});

      container
          .read(readerSettingsProvider.notifier)
          .setFuriganaWanikaniMinStage(5);
      expect(container.read(wanikaniKnownKanjiProvider), {
        rune('日'),
        rune('本'),
      });

      container
          .read(readerSettingsProvider.notifier)
          .setFuriganaWanikaniMinStage(1);
      expect(container.read(wanikaniKnownKanjiProvider), {
        rune('日'),
        rune('本'),
        rune('語'),
      });
    });

    test('updates after a sync and empties after unlink', () async {
      storage.token = 'tok';
      final container = makeContainer();
      final notifier = container.read(wanikaniProvider.notifier);
      await notifier.loadPersistedSettings();
      expect(container.read(wanikaniKnownKanjiProvider), isEmpty);

      await notifier.syncNow();
      expect(container.read(wanikaniKnownKanjiProvider), {rune('日')});

      await notifier.unlink();
      expect(container.read(wanikaniKnownKanjiProvider), isEmpty);
    });
  });
}
