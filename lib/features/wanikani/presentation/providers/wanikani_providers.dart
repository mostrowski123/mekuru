import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';

import '../../data/models/wanikani_snapshot.dart';
import '../../data/services/wanikani_api_client.dart';
import '../../data/services/wanikani_storage.dart';

final wanikaniApiClientProvider = Provider<WanikaniApiClient>(
  (_) => WanikaniApiClient(),
);

final wanikaniStorageProvider = Provider<WanikaniStorage>(
  (_) => const WanikaniStorage(),
);

/// Clock seam so the staleness gate is testable.
final wanikaniClockProvider = Provider<DateTime Function()>(
  (_) => DateTime.now,
);

/// How old a snapshot may be before the silent startup/resume refresh
/// re-syncs. Manual "Sync now" ignores this.
const wanikaniRefreshInterval = Duration(hours: 1);

@immutable
class WanikaniState {
  /// A token is stored — the account can be synced.
  final bool linked;

  /// The last successful sync. Can exist without [linked] after a backup
  /// restore (the snapshot is backed up, the token is not).
  final WanikaniSnapshot? snapshot;

  final bool syncing;

  const WanikaniState({
    this.linked = false,
    this.snapshot,
    this.syncing = false,
  });

  Map<int, int> get stages => snapshot?.stages ?? const {};

  bool get hasKanji => stages.isNotEmpty;

  WanikaniState copyWith({
    bool? linked,
    WanikaniSnapshot? snapshot,
    bool? syncing,
  }) => WanikaniState(
    linked: linked ?? this.linked,
    snapshot: snapshot ?? this.snapshot,
    syncing: syncing ?? this.syncing,
  );
}

/// Owns the WaniKani link: token + snapshot persistence, the sync round
/// trip, and the two refresh policies (silent-and-swallowing for startup
/// and resume, throwing for the settings screen's "Sync now").
class WanikaniNotifier extends Notifier<WanikaniState> {
  Future<void>? _persistedSettingsLoad;
  bool _persistedSettingsLoaded = false;

  /// The sync currently running, shared by overlapping callers so a manual
  /// refresh during the startup one awaits it instead of doubling requests.
  Future<WanikaniSnapshot?>? _inFlight;

  @override
  WanikaniState build() => const WanikaniState();

  /// Idempotent: every caller awaits the same first load.
  Future<void> loadPersistedSettings() =>
      _persistedSettingsLoad ??= _loadPersistedSettings();

  Future<void> _loadPersistedSettings() async {
    final storage = ref.read(wanikaniStorageProvider);
    final (token, snapshot) = await (
      storage.loadToken(),
      storage.loadSnapshot(),
    ).wait;
    if (!ref.mounted) return;
    state = state.copyWith(linked: token != null, snapshot: snapshot);
    _persistedSettingsLoaded = true;
  }

  /// Validates [token] against the account, pulls the kanji stages, and only
  /// then stores both. Throws (a [WanikaniException] for API conditions) and
  /// leaves any existing link untouched on failure.
  Future<void> link(String token) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      throw const WanikaniException(WanikaniException.tokenInvalid);
    }
    // Let a sync for the previous token finish so it cannot overwrite the
    // new account's snapshot afterwards.
    final previous = _inFlight;
    if (previous != null) {
      try {
        await previous;
      } catch (_) {
        // The old link's failure is not this call's concern.
      }
    }
    final snapshot = await _runSync(trimmed, trigger: 'link');
    await ref.read(wanikaniStorageProvider).saveToken(trimmed);
    if (!ref.mounted) return;
    state = state.copyWith(linked: true, snapshot: snapshot);
    logUsage(
      'wanikani.linked',
      attrs: {'level': snapshot.level, 'kanji_count': snapshot.stages.length},
    );
  }

  Future<void> unlink() async {
    final storage = ref.read(wanikaniStorageProvider);
    await (storage.clearToken(), storage.clearSnapshot()).wait;
    if (!ref.mounted) return;
    state = const WanikaniState();
    logUsage('wanikani.unlinked');
  }

  /// Manual refresh from the settings screen: rethrows so the UI can show
  /// what went wrong.
  Future<void> syncNow() => _refresh(trigger: 'manual', rethrowErrors: true);

  /// Silent refresh for startup and resume: skipped unless linked and the
  /// snapshot is older than [wanikaniRefreshInterval]; never throws.
  Future<void> refreshIfDue({required String trigger}) async {
    // The decision reads persisted state, so make sure it is in. Skipping
    // the await once loaded keeps the in-flight registration synchronous
    // for a link() issued right after.
    if (!_persistedSettingsLoaded) await loadPersistedSettings();
    if (!ref.mounted || !state.linked) return;
    final syncedAt = state.snapshot?.syncedAt;
    if (syncedAt != null) {
      final age = ref.read(wanikaniClockProvider)().difference(syncedAt);
      if (age < wanikaniRefreshInterval) return;
    }
    await _refresh(trigger: trigger, rethrowErrors: false);
  }

  Future<void> _refresh({
    required String trigger,
    required bool rethrowErrors,
  }) async {
    // Registered synchronously so a link() issued right after sees it.
    final pending = _inFlight ??= _syncStoredToken(
      trigger,
    ).whenComplete(() => _inFlight = null);
    try {
      final snapshot = await pending;
      if (!ref.mounted) return;
      if (snapshot == null) {
        // Secure storage lost the token (or never had it): reflect it.
        state = state.copyWith(linked: false);
        return;
      }
      state = state.copyWith(snapshot: snapshot);
    } catch (_) {
      if (rethrowErrors) rethrow;
    }
  }

  /// Null when no token is stored; otherwise the synced snapshot.
  Future<WanikaniSnapshot?> _syncStoredToken(String trigger) async {
    final token = await ref.read(wanikaniStorageProvider).loadToken();
    if (token == null) return null;
    return _runSync(token, trigger: trigger);
  }

  /// One network round-trip plus persistence. Telemetry records outcomes
  /// with the trigger and error code only — never the token or username.
  Future<WanikaniSnapshot> _runSync(
    String token, {
    required String trigger,
  }) async {
    if (ref.mounted) state = state.copyWith(syncing: true);
    final stopwatch = Stopwatch()..start();
    try {
      final client = ref.read(wanikaniApiClientProvider);
      final user = await client.fetchUser(token);
      final kanji = await client.fetchKanjiStages(
        token,
        subjectRunes: state.snapshot?.subjectRunes ?? const {},
      );
      final snapshot = WanikaniSnapshot(
        username: user.username,
        level: user.level,
        stages: kanji.stages,
        subjectRunes: kanji.subjectRunes,
        syncedAt: ref.read(wanikaniClockProvider)(),
      );
      await ref.read(wanikaniStorageProvider).saveSnapshot(snapshot);
      logUsage(
        'wanikani.synced',
        attrs: {
          'trigger': trigger,
          'kanji_count': kanji.stages.length,
          'duration_ms': stopwatch.elapsedMilliseconds,
        },
      );
      return snapshot;
    } catch (e, stackTrace) {
      // Expected API conditions stay breadcrumbs; a malformed payload or an
      // unknown error is a bug and files a Sentry issue via the stack trace.
      final code = e is WanikaniException ? e.code : 'unexpected';
      final isBug = code == WanikaniException.malformed || code == 'unexpected';
      logFailure(
        'wanikani.synced',
        e,
        stackTrace: isBug ? stackTrace : null,
        attrs: {'trigger': trigger, 'code': code},
      );
      rethrow;
    } finally {
      if (ref.mounted) state = state.copyWith(syncing: false);
    }
  }
}

final wanikaniProvider = NotifierProvider<WanikaniNotifier, WanikaniState>(
  WanikaniNotifier.new,
);

/// The kanji (runes) currently counted as known: the snapshot filtered by
/// the reader's WaniKani stage threshold. This is the only WaniKani input
/// the reader watches, so a threshold change and a background sync each
/// re-annotate exactly once. Empty when nothing is synced, which makes
/// [FuriganaMode.wanikani] behave like "all kanji".
final wanikaniKnownKanjiProvider = Provider<Set<int>>((ref) {
  final snapshot = ref.watch(wanikaniProvider.select((s) => s.snapshot));
  final minStage = ref.watch(
    readerSettingsProvider.select((s) => s.furiganaWanikaniMinStage),
  );
  return snapshot?.knownKanji(minStage) ?? const {};
});
