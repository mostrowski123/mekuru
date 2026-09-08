import 'package:mekuru/core/platform/full_backup_job_api.dart';

/// Scriptable stand-in for the native job service.
class FakeFullBackupJobApi implements FullBackupJobApi {
  final calls = <String>[];
  final committed = <Map<String, Object?>>[];

  /// What [status] returns; tests advance it to script a job's life.
  FullBackupJobStatus current = FullBackupJobStatus.none;

  /// When set, each [status] call pops the next value until it runs dry.
  List<FullBackupJobStatus> statusScript = [];

  Object? commitError;
  ZipInspection? inspection = const ZipInspection(isZip: true, text: '{}');
  FullBackupJobStatus? result;
  bool cancelResult = true;
  bool permissionGranted = true;

  @override
  Future<void> commitJob(Map<String, Object?> spec) async {
    calls.add('commitJob');
    if (commitError != null) throw commitError!;
    committed.add(spec);
  }

  @override
  Future<FullBackupJobStatus> status() async {
    calls.add('status');
    if (statusScript.isNotEmpty) current = statusScript.removeAt(0);
    return current;
  }

  @override
  Future<bool> cancel() async {
    calls.add('cancel');
    return cancelResult;
  }

  @override
  Future<FullBackupJobStatus?> consumeResult() async {
    calls.add('consumeResult');
    final value = result;
    result = null;
    return value;
  }

  @override
  Future<bool> requestNotificationPermission() async {
    calls.add('requestNotificationPermission');
    return permissionGranted;
  }

  @override
  Future<ZipInspection?> inspectZip({
    required String uri,
    required String name,
  }) async {
    calls.add('inspectZip');
    return inspection;
  }
}
