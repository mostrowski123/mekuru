import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// [download] is a server book, [dictionary] a dictionary download.
enum BackgroundJobKind { download, scan, dictionary }

/// Live Activity text for the running work: what is being done and how far
/// along it is (0-100).
typedef BackgroundWorkText =
    ({String title, String subtitle}) Function({
      required int downloads,
      required int scans,
      required int dictionaries,
      required int percent,
    });

/// Keeps Mekuru running after the user leaves it while work they started is
/// in progress: server book and dictionary downloads and OCR scans. On iOS one
/// BGContinuedProcessingTask (`BackgroundWorkBridge` in AppDelegate.swift)
/// covers all of it, and the system shows the combined progress in a Live
/// Activity the user can cancel. When the system or the user ends that task,
/// every job's `onStopped` runs and that work must stop. Elsewhere this does
/// nothing: Android runs the same work as WorkManager jobs.
class BackgroundWork {
  BackgroundWork._(this._channel);

  static final instance = BackgroundWork._(
    const MethodChannel('mekuru/background_work'),
  );

  @visibleForTesting
  factory BackgroundWork.forTesting(MethodChannel channel) =>
      BackgroundWork._(channel);

  final MethodChannel _channel;
  bool _listening = false;
  final _jobs = <String, _Job>{};
  bool _open = false;
  Timer? _pendingUpdate;
  DateTime _lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  /// Localized Live Activity text; set by the app once localizations exist.
  BackgroundWorkText? text;

  static bool get _supported => defaultTargetPlatform == TargetPlatform.iOS;

  /// Work [id] of [kind] began. [onStopped] runs if the system or the user
  /// ends the background task; the work must then stop.
  void start(
    String id,
    BackgroundJobKind kind, {
    required VoidCallback onStopped,
  }) {
    if (!_supported) return;
    // Only now: progress() also runs where no binding exists (Android's
    // WorkManager isolate, host tests), and must stay a no-op there.
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler(_onNativeCall);
    }
    _jobs[id] = _Job(kind, onStopped);
    if (!_open) {
      _open = true;
      final text = _text();
      unawaited(
        _channel
            .invokeMethod<bool>('begin', {
              'title': text.title,
              'subtitle': text.subtitle,
            })
            .catchError((Object _) => false),
      );
    }
    _scheduleUpdate();
  }

  /// [id] is [fraction] (0..1) done.
  void progress(String id, double fraction) {
    final job = _jobs[id];
    if (job == null) return;
    job.fraction = fraction.clamp(0.0, 1.0);
    _scheduleUpdate();
  }

  /// [id] ended (done, failed or cancelled).
  void finish(String id) {
    if (!_jobs.containsKey(id)) return;
    if (_jobs.length > 1) {
      _jobs.remove(id);
      _scheduleUpdate();
      return;
    }
    _pendingUpdate?.cancel();
    _pendingUpdate = null;
    // The last progress the throttle may still be holding, so the Live
    // Activity ends where the work did (100% when it succeeded).
    _sendUpdate();
    _jobs.remove(id);
    if (_open) {
      _open = false;
      unawaited(
        _channel.invokeMethod<void>('end', true).catchError((Object _) {}),
      );
    }
  }

  bool isRunning(String id) => _jobs.containsKey(id);

  Future<void> _onNativeCall(MethodCall call) async {
    if (call.method != 'expired') return;
    _open = false;
    _pendingUpdate?.cancel();
    _pendingUpdate = null;
    final stopped = [..._jobs.values];
    _jobs.clear();
    for (final job in stopped) {
      job.onStopped();
    }
  }

  /// At most two updates a second; the system only needs steady progress.
  void _scheduleUpdate() {
    if (!_open || _pendingUpdate != null) return;
    final wait =
        const Duration(milliseconds: 500) -
        DateTime.now().difference(_lastUpdate);
    _pendingUpdate = Timer(wait.isNegative ? Duration.zero : wait, () {
      _pendingUpdate = null;
      _sendUpdate();
    });
  }

  void _sendUpdate() {
    if (!_open || _jobs.isEmpty) return;
    _lastUpdate = DateTime.now();
    final total = _jobs.length * 1000;
    final completed = _jobs.values.fold<int>(
      0,
      (sum, job) => sum + (job.fraction * 1000).round(),
    );
    final text = _text(percent: completed * 100 ~/ total);
    unawaited(
      _channel
          .invokeMethod<void>('update', {
            'completed': completed,
            'total': total,
            'title': text.title,
            'subtitle': text.subtitle,
          })
          .catchError((Object _) {}),
    );
  }

  ({String title, String subtitle}) _text({int percent = 0}) {
    int count(BackgroundJobKind kind) =>
        _jobs.values.where((j) => j.kind == kind).length;
    return text?.call(
          downloads: count(BackgroundJobKind.download),
          scans: count(BackgroundJobKind.scan),
          dictionaries: count(BackgroundJobKind.dictionary),
          percent: percent,
        ) ??
        (title: 'Mekuru', subtitle: '$percent%');
  }
}

class _Job {
  final BackgroundJobKind kind;
  final VoidCallback onStopped;
  double fraction = 0;

  _Job(this.kind, this.onStopped);
}
