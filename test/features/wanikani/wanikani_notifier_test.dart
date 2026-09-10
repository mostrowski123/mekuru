import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/features/wanikani/data/models/wanikani_snapshot.dart';
import 'package:mekuru/features/wanikani/presentation/providers/wanikani_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/wanikani_test_fakes.dart';

void main() {
  final now = DateTime.utc(2026, 9, 10, 12);
  final yesterday = now.subtract(const Duration(days: 1));
  late FakeWanikaniApiClient client;
  late FakeWanikaniStorage storage;
  late DateTime clock;
  late List<String> events;
  late List<String> warnings;
  late ProviderContainer container;

  /// The notifier with persisted state loaded, as app startup leaves it.
  Future<WanikaniNotifier> loadedNotifier() async {
    final notifier = container.read(wanikaniProvider.notifier);
    await notifier.loadPersistedSettings();
    return notifier;
  }

  WanikaniState state() => container.read(wanikaniProvider);

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
    container = ProviderContainer(
      overrides: [
        wanikaniApiClientProvider.overrideWithValue(client),
        wanikaniStorageProvider.overrideWithValue(storage),
        wanikaniClockProvider.overrideWithValue(() => clock),
      ],
    );
    addTearDown(container.dispose);
  });

  tearDown(() {
    usageLogSinkOverride = null;
  });

  group('loadPersistedSettings', () {
    test('restores a linked account with its snapshot', () async {
      storage
        ..token = 'tok'
        ..snapshot = snapshotAt(now);
      await loadedNotifier();

      expect(state().linked, isTrue);
      expect(state().hasKanji, isTrue);
      expect(state().syncing, isFalse);
    });

    test('a snapshot without a token is restored but not linked', () async {
      storage.snapshot = snapshotAt(now);
      await loadedNotifier();

      expect(state().linked, isFalse);
      expect(state().hasKanji, isTrue);
    });

    test('nothing stored means unlinked and empty', () async {
      await loadedNotifier();

      expect(state().linked, isFalse);
      expect(state().snapshot, isNull);
      expect(state().stages, isEmpty);
    });

    test('runs once', () async {
      storage.token = 'tok';
      final notifier = await loadedNotifier();
      storage.token = null;
      await notifier.loadPersistedSettings();
      expect(state().linked, isTrue);
    });
  });

  group('link', () {
    test('validates, syncs, then persists token and snapshot', () async {
      await container.read(wanikaniProvider.notifier).link('  tok-1  ');

      expect(client.tokens, ['tok-1']);
      expect(storage.token, 'tok-1');
      expect(storage.snapshot!.username, 'crabigator');
      expect(storage.snapshot!.syncedAt, now);
      expect(storage.snapshot!.subjectRunes, client.subjectRunes);
      expect(state().linked, isTrue);
      expect(state().stages, {rune('日'): 9, rune('本'): 5});
      expect(state().syncing, isFalse);
      expect(events, ['wanikani.synced', 'wanikani.linked']);
      expect(warnings, isEmpty);
    });

    test('a rejected token writes nothing and keeps the old link', () async {
      storage
        ..token = 'old'
        ..snapshot = snapshotAt(yesterday);
      final notifier = await loadedNotifier();
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
      expect(state().linked, isTrue);
      expect(state().snapshot!.syncedAt, yesterday);
      expect(state().syncing, isFalse);
      expect(events, isEmpty);
      expect(warnings, ['wanikani.synced']);
    });

    test('a blank token is rejected without a request', () async {
      await expectLater(
        () => container.read(wanikaniProvider.notifier).link('   '),
        throwsA(isA<WanikaniException>()),
      );
      expect(client.userCalls, 0);
    });

    test('waits for an in-flight sync before linking', () async {
      storage
        ..token = 'old'
        ..snapshot = snapshotAt(yesterday);
      final notifier = await loadedNotifier();

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
      final notifier = await loadedNotifier();

      await notifier.unlink();

      expect(storage.token, isNull);
      expect(storage.snapshot, isNull);
      expect(state().linked, isFalse);
      expect(state().snapshot, isNull);
      expect(events, ['wanikani.unlinked']);
    });
  });

  group('refreshIfDue', () {
    test('loads persisted state itself before deciding', () async {
      storage.token = 'tok';
      // No explicit loadPersistedSettings(): app.dart fires both unawaited.
      await container
          .read(wanikaniProvider.notifier)
          .refreshIfDue(trigger: 'startup');
      expect(client.userCalls, 1);
      expect(state().linked, isTrue);
    });

    test('does nothing when unlinked, even with a restored snapshot', () async {
      storage.snapshot = snapshotAt(now.subtract(const Duration(days: 3)));
      final notifier = await loadedNotifier();

      await notifier.refreshIfDue(trigger: 'startup');
      expect(client.userCalls, 0);
    });

    test('skips a fresh snapshot', () async {
      storage
        ..token = 'tok'
        ..snapshot = snapshotAt(now.subtract(const Duration(minutes: 59)));
      final notifier = await loadedNotifier();

      await notifier.refreshIfDue(trigger: 'startup');
      expect(client.userCalls, 0);
    });

    test('re-syncs a stale snapshot, reusing the cached catalogue', () async {
      final stale = snapshotAt(
        now.subtract(const Duration(hours: 2)),
        stages: {rune('日'): 1},
      );
      storage
        ..token = 'tok'
        ..snapshot = stale;
      final notifier = await loadedNotifier();

      Map<String, Object?>? syncedAttrs;
      usageLogSinkOverride = (message, attributes, {required isWarning}) {
        if (message == 'wanikani.synced') syncedAttrs = attributes;
      };
      await notifier.refreshIfDue(trigger: 'resume');

      expect(client.userCalls, 1);
      expect(client.tokens, ['tok']);
      expect(client.receivedSubjectRunes, [stale.subjectRunes]);
      expect(state().stages, {rune('日'): 9, rune('本'): 5});
      expect(state().snapshot!.syncedAt, now);
      expect(storage.snapshot!.syncedAt, now);
      expect(syncedAttrs, isNotNull);
      expect(syncedAttrs!.keys, containsAll(['trigger', 'kanji_count']));
    });

    test('syncs when linked without any snapshot', () async {
      storage.token = 'tok';
      final notifier = await loadedNotifier();

      await notifier.refreshIfDue(trigger: 'startup');
      expect(client.userCalls, 1);
      expect(client.receivedSubjectRunes, [isEmpty]);
      expect(state().hasKanji, isTrue);
    });

    test('swallows failures and leaves the old snapshot', () async {
      final old = snapshotAt(yesterday);
      storage
        ..token = 'tok'
        ..snapshot = old;
      client.error = const WanikaniException(WanikaniException.network);
      final notifier = await loadedNotifier();

      await notifier.refreshIfDue(trigger: 'startup');

      expect(state().snapshot, same(old));
      expect(state().linked, isTrue);
      expect(state().syncing, isFalse);
      expect(warnings, ['wanikani.synced']);
    });

    test('a token that vanished from secure storage unlinks', () async {
      storage.token = 'tok';
      final notifier = await loadedNotifier();
      storage.token = null;

      await notifier.refreshIfDue(trigger: 'startup');
      expect(client.userCalls, 0);
      expect(state().linked, isFalse);
    });
  });

  group('syncNow', () {
    test('rethrows so the UI can show the error', () async {
      storage.token = 'tok';
      client.error = const WanikaniException(
        WanikaniException.rateLimited,
        statusCode: 429,
      );
      final notifier = await loadedNotifier();

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
      expect(state().syncing, isFalse);
    });

    test('ignores the staleness gate', () async {
      storage
        ..token = 'tok'
        ..snapshot = snapshotAt(now);
      final notifier = await loadedNotifier();

      await notifier.syncNow();
      expect(client.userCalls, 1);
    });

    test('overlapping calls share one round-trip', () async {
      storage.token = 'tok';
      final notifier = await loadedNotifier();

      client.gate = Completer<void>();
      final first = notifier.syncNow();
      final second = notifier.syncNow();
      await Future<void>.delayed(Duration.zero);
      expect(state().syncing, isTrue);
      client.gate!.complete();
      await Future.wait([first, second]);

      expect(client.userCalls, 1);
      expect(client.stagesCalls, 1);
      expect(state().syncing, isFalse);
    });

    test('a shared failure reaches the manual caller only', () async {
      storage.token = 'tok';
      client.error = const WanikaniException(WanikaniException.network);
      final notifier = await loadedNotifier();

      client.gate = Completer<void>();
      final silent = notifier.refreshIfDue(trigger: 'startup');
      final manual = expectLater(
        notifier.syncNow(),
        throwsA(isA<WanikaniException>()),
      );
      client.gate!.complete();

      await silent;
      await manual;
      expect(client.userCalls, 1);
    });

    test('unexpected errors are reported as bugs', () async {
      storage.token = 'tok';
      client.error = StateError('boom');
      final notifier = await loadedNotifier();

      await expectLater(notifier.syncNow, throwsStateError);
      expect(warnings, ['wanikani.synced']);
    });
  });

  group('wanikaniKnownKanjiProvider', () {
    Set<int> known() => container.read(wanikaniKnownKanjiProvider);

    test('is empty without a snapshot', () {
      expect(known(), isEmpty);
    });

    test('filters by the reader threshold and follows changes', () async {
      storage
        ..token = 'tok'
        ..snapshot = snapshotAt(
          now,
          stages: {rune('日'): 9, rune('本'): 5, rune('語'): 1},
        );
      await loadedNotifier();
      final reader = container.read(readerSettingsProvider.notifier);

      expect(known(), {rune('日')});

      reader.setFuriganaWanikaniMinStage(5);
      expect(known(), {rune('日'), rune('本')});

      reader.setFuriganaWanikaniMinStage(1);
      expect(known(), {rune('日'), rune('本'), rune('語')});
    });

    test('updates after a sync and empties after unlink', () async {
      storage.token = 'tok';
      final notifier = await loadedNotifier();
      expect(known(), isEmpty);

      await notifier.syncNow();
      expect(known(), {rune('日')});

      await notifier.unlink();
      expect(known(), isEmpty);
    });
  });
}
