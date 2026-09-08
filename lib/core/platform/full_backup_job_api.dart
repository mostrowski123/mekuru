import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Another job is running or waiting to resume.
class FullBackupJobBusyException implements Exception {
  const FullBackupJobBusyException();
}

enum FullBackupJobKind { export, restore }

/// Lifecycle of the one job the Kotlin service can hold.
enum FullBackupJobLifecycle { none, running, paused, done, cancelled, failed }

/// A snapshot of the job as the service reports it.
class FullBackupJobStatus {
  final FullBackupJobLifecycle lifecycle;
  final FullBackupJobKind kind;

  /// `preparing | writing | checking | extracting | finishing` while running.
  final String phase;
  final int done;
  final int total;

  /// Failure code (`failed`) or why the last run stopped (`paused`).
  final String? error;

  // Export result fields.
  final String? location;
  final int bytes;
  final int entries;
  final int skippedFiles;
  final bool renamed;

  const FullBackupJobStatus({
    required this.lifecycle,
    this.kind = FullBackupJobKind.export,
    this.phase = '',
    this.done = 0,
    this.total = 0,
    this.error,
    this.location,
    this.bytes = 0,
    this.entries = 0,
    this.skippedFiles = 0,
    this.renamed = true,
  });

  static const none = FullBackupJobStatus(
    lifecycle: FullBackupJobLifecycle.none,
  );

  @override
  bool operator ==(Object other) =>
      other is FullBackupJobStatus &&
      other.lifecycle == lifecycle &&
      other.kind == kind &&
      other.phase == phase &&
      other.done == done &&
      other.total == total &&
      other.error == error &&
      other.location == location &&
      other.bytes == bytes &&
      other.entries == entries &&
      other.skippedFiles == skippedFiles &&
      other.renamed == renamed;

  @override
  int get hashCode => Object.hash(
    lifecycle,
    kind,
    phase,
    done,
    total,
    error,
    location,
    bytes,
    entries,
    skippedFiles,
    renamed,
  );

  bool get isActive =>
      lifecycle == FullBackupJobLifecycle.running ||
      lifecycle == FullBackupJobLifecycle.paused;

  bool get isTerminal =>
      lifecycle == FullBackupJobLifecycle.done ||
      lifecycle == FullBackupJobLifecycle.cancelled ||
      lifecycle == FullBackupJobLifecycle.failed;

  factory FullBackupJobStatus.fromMap(Map<Object?, Object?> map) {
    int number(String key) => (map[key] as num?)?.toInt() ?? 0;
    return FullBackupJobStatus(
      lifecycle: FullBackupJobLifecycle.values.firstWhere(
        (v) => v.name == map['status'],
        orElse: () => FullBackupJobLifecycle.none,
      ),
      kind: map['kind'] == 'restore'
          ? FullBackupJobKind.restore
          : FullBackupJobKind.export,
      phase: (map['phase'] as String?) ?? '',
      done: number('done'),
      total: number('total'),
      error: map['error'] as String?,
      location: map['location'] as String?,
      bytes: number('bytes'),
      entries: number('entries'),
      skippedFiles: number('skippedFiles'),
      renamed: map['renamed'] != false,
    );
  }
}

/// What a restore learns about an archive before committing to it.
class ZipInspection {
  /// False when the file does not start with a zip signature at all.
  final bool isZip;
  final String? text;

  /// Whether the file ends with a central directory; null when the source
  /// cannot be seeked to find out.
  final bool? complete;

  const ZipInspection({required this.isZip, this.text, this.complete});
}

/// The job service as seen from Dart; [FullBackupJobChannel] is the real
/// one, tests substitute a fake.
abstract interface class FullBackupJobApi {
  /// Hands a fully prepared job to the service. Throws
  /// [FullBackupJobBusyException] when one already exists.
  Future<void> commitJob(Map<String, Object?> spec);

  Future<FullBackupJobStatus> status();

  /// True when the job was cancelled (false once a restore has committed).
  Future<bool> cancel();

  /// Returns and clears the terminal result, if any.
  Future<FullBackupJobStatus?> consumeResult();

  /// Asks for POST_NOTIFICATIONS on Android 13+. The answer never blocks
  /// a job; a denied permission only hides the progress notification.
  Future<bool> requestNotificationPermission();

  Future<ZipInspection?> inspectZip({
    required String uri,
    required String name,
  });
}

class FullBackupJobChannel implements FullBackupJobApi {
  const FullBackupJobChannel();

  static const MethodChannel _channel = MethodChannel('mekuru/full_backup_job');

  @override
  Future<void> commitJob(Map<String, Object?> spec) async {
    try {
      await _channel.invokeMethod<void>('commitJob', spec);
    } on PlatformException catch (e) {
      if (e.code == 'busy') throw const FullBackupJobBusyException();
      rethrow;
    }
  }

  @override
  Future<FullBackupJobStatus> status() async {
    try {
      final value = await _channel.invokeMethod<Object?>('status');
      if (value is! Map) return FullBackupJobStatus.none;
      return FullBackupJobStatus.fromMap(value);
    } on MissingPluginException {
      return FullBackupJobStatus.none;
    } on PlatformException catch (e) {
      debugPrint('[FullBackupJob] status failed: $e');
      return FullBackupJobStatus.none;
    }
  }

  @override
  Future<bool> cancel() async =>
      await _channel.invokeMethod<bool>('cancel') ?? false;

  @override
  Future<FullBackupJobStatus?> consumeResult() async {
    final value = await _channel.invokeMethod<Object?>('consumeResult');
    return value is Map ? FullBackupJobStatus.fromMap(value) : null;
  }

  @override
  Future<bool> requestNotificationPermission() async {
    try {
      return await _channel.invokeMethod<bool>(
            'requestNotificationPermission',
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<ZipInspection?> inspectZip({
    required String uri,
    required String name,
  }) async {
    final value = await _channel.invokeMethod<Object?>('inspectZip', {
      'uri': uri,
      'name': name,
    });
    if (value is! Map) return null;
    return ZipInspection(
      isZip: value['isZip'] == true,
      text: value['text'] as String?,
      complete: value['complete'] as bool?,
    );
  }

  // ── Debug-only seams for the emulator suites (refused in release builds).
  // Deliberately not on [FullBackupJobApi]: nothing in the app calls them.

  Future<bool> abortForTest({required int afterBytes}) async =>
      await _channel.invokeMethod<bool>('abortForTest', {
        'afterBytes': afterBytes,
      }) ??
      false;

  Future<void> recoverForTest() =>
      _channel.invokeMethod<void>('recoverForTest');

  Future<bool> isServiceRunning() async =>
      await _channel.invokeMethod<bool>('isServiceRunning') ?? false;

  Future<bool> notificationsEnabled() async =>
      await _channel.invokeMethod<bool>('notificationsEnabled') ?? false;

  Future<List<int>> activeNotificationIds() async {
    final value = await _channel.invokeMethod<List<Object?>>(
      'activeNotificationIds',
    );
    return value?.map((e) => (e as num).toInt()).toList() ?? const [];
  }

  Future<void> setForceNonResumableForTest(bool value) => _channel
      .invokeMethod<void>('setForceNonResumableForTest', {'value': value});
}
