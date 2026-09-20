import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/platform/full_backup_job_api.dart';
import 'package:mekuru/features/backup/data/services/ios_full_backup.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// The native job service; tests substitute a fake.
final fullBackupJobApiProvider = Provider<FullBackupJobApi>(
  (ref) => const FullBackupJobChannel(),
);

/// True when `main` found a job (or an unconsumed result) on disk before
/// the first frame, so the blocking page is the first thing on screen.
final initialFullBackupJobPendingProvider = Provider<bool>((ref) => false);

/// Ends the process so the staged restore applies on the next cold start.
/// `SystemNavigator.pop` would keep the engine (and the open database)
/// alive, so a real exit is the only deterministic trigger.
final appExitProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    try {
      await Sentry.close().timeout(const Duration(seconds: 3));
    } catch (_) {
      // Flushing is best effort; captured events persist on disk anyway.
    }
    exit(0);
  };
});

enum FullBackupJobStage {
  none,

  /// Dart is still snapshotting and planning; nothing is committed yet.
  preparing,

  /// The native service has the job (running, or paused until it resumes).
  active,

  /// Finished one way or another; the page shows the outcome until dismissed.
  terminal,
}

class FullBackupJobState {
  final FullBackupJobStage stage;
  final FullBackupJobStatus status;

  const FullBackupJobState({
    this.stage = FullBackupJobStage.none,
    this.status = FullBackupJobStatus.none,
  });

  FullBackupJobKind get kind => status.kind;

  /// While true the app is hidden behind the job page.
  bool get blocksApp => stage != FullBackupJobStage.none;

  @override
  bool operator ==(Object other) =>
      other is FullBackupJobState &&
      other.stage == stage &&
      other.status == status;

  @override
  int get hashCode => Object.hash(stage, status);
}

/// Mirrors the native job for the UI: polls the service while a job is
/// active, hands out the terminal outcome once, and drives cancel, dismiss
/// and the post-restore exit.
class FullBackupJobNotifier extends Notifier<FullBackupJobState> {
  Timer? _timer;
  static const pollEvery = Duration(milliseconds: 500);

  @override
  FullBackupJobState build() {
    ref.onDispose(_stopPolling);
    if (ref.watch(initialFullBackupJobPendingProvider)) {
      // Show the page before the first poll answers; the poll decides
      // whether it is a running job or a result waiting to be read.
      _startPolling();
      return const FullBackupJobState(stage: FullBackupJobStage.active);
    }
    return const FullBackupJobState();
  }

  /// Re-reads the service. Cheap; called by the poll, on app resume and
  /// after every action.
  Future<void> refresh() async {
    if (state.stage == FullBackupJobStage.preparing) return;
    final status = await ref.read(fullBackupJobApiProvider).status();
    final next = switch (status.lifecycle) {
      FullBackupJobLifecycle.none => const FullBackupJobState(),
      FullBackupJobLifecycle.running || FullBackupJobLifecycle.paused =>
        FullBackupJobState(stage: FullBackupJobStage.active, status: status),
      FullBackupJobLifecycle.done ||
      FullBackupJobLifecycle.cancelled ||
      FullBackupJobLifecycle.failed => FullBackupJobState(
        stage: FullBackupJobStage.terminal,
        status: status,
      ),
    };
    final before = state;
    if (next != state) state = next;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await _followOnIos(before, next);
    }
    if (next.stage == FullBackupJobStage.active) {
      _startPolling();
    } else {
      _stopPolling();
    }
  }

  /// The flow is snapshotting/planning on the Dart side: block the app now.
  void markPreparing(FullBackupJobKind kind) {
    state = FullBackupJobState(
      stage: FullBackupJobStage.preparing,
      status: FullBackupJobStatus(
        lifecycle: FullBackupJobLifecycle.none,
        kind: kind,
      ),
    );
  }

  /// The job is committed to the service; start following it.
  Future<void> jobCommitted(FullBackupJobKind kind) async {
    state = FullBackupJobState(
      stage: FullBackupJobStage.active,
      status: FullBackupJobStatus(
        lifecycle: FullBackupJobLifecycle.running,
        kind: kind,
      ),
    );
    await refresh();
  }

  /// Preparation failed before anything was committed: release the app.
  void preparationFailed() {
    state = const FullBackupJobState();
  }

  Future<void> cancel() async {
    await ref.read(fullBackupJobApiProvider).cancel();
    await refresh();
  }

  /// iOS runs the job inside the app: keep the phone awake while it works,
  /// and when an export finishes, let the user move the zip out of the app.
  Future<void> _followOnIos(
    FullBackupJobState before,
    FullBackupJobState next,
  ) async {
    final active = next.stage == FullBackupJobStage.active;
    if (active != (before.stage == FullBackupJobStage.active)) {
      await WakelockPlus.toggle(enable: active);
    }
    if (before.stage != FullBackupJobStage.active ||
        next.stage != FullBackupJobStage.terminal) {
      return;
    }
    final status = next.status;
    if (status.kind == FullBackupJobKind.export &&
        status.lifecycle == FullBackupJobLifecycle.done) {
      await saveExportedZip();
    } else {
      await IosFullBackup.cleanUp();
    }
  }

  /// iOS: asks where the finished zip should go and moves it there. The job
  /// page offers this again while the file is still in the app.
  Future<void> saveExportedZip() async {
    final path = state.status.location;
    if (path == null || !File(path).existsSync()) return;
    await IosFullBackup.saveElsewhere(path);
    // The page reads whether the file is still there.
    ref.notifyListeners();
  }

  /// Acknowledges a terminal outcome and releases the app.
  Future<void> dismiss() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // An export the user chose not to save goes with the dismissal.
      await IosFullBackup.cleanUp(exportedZip: state.status.location);
    }
    await ref.read(fullBackupJobApiProvider).consumeResult();
    _stopPolling();
    state = const FullBackupJobState();
  }

  Future<void> exitApp() => ref.read(appExitProvider)();

  void _startPolling() {
    _timer ??= Timer.periodic(pollEvery, (_) => refresh());
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
  }
}

final fullBackupJobProvider =
    NotifierProvider<FullBackupJobNotifier, FullBackupJobState>(
      FullBackupJobNotifier.new,
    );
