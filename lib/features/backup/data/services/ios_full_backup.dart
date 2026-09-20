import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/full_backup_endpoints.dart';
import 'dart_full_backup_job.dart';
import 'full_backup_service.dart';

/// The iOS side of full backup. Android hands the job to a foreground service
/// and SAF; iOS can only work while the app is open, so the job runs in
/// process ([DartFullBackupJob]) and files come and go through the document
/// picker (`FilesBridge` in `AppDelegate.swift`).
abstract final class IosFullBackup {
  static const _files = MethodChannel('mekuru/ios_files');

  /// The one job object of this process, created by [start] in `main`: its
  /// state lives in memory, so every caller must share it.
  static DartFullBackupJob? job;

  /// The zip the user picked to restore: a copy in the app's temp folder,
  /// which is the app's to delete.
  static String? _pickedZip;

  /// Call once at boot, after the staged-restore hook.
  static Future<DartFullBackupJob> start() async {
    final created = DartFullBackupJob(
      root: await getApplicationSupportDirectory(),
    );
    await created.recover();
    return job = created;
  }

  /// Exports are written inside the app first and moved out afterwards
  /// ([saveElsewhere]): the picker can only hand over a finished file.
  static Future<FullBackupTarget> exportTarget() async => FullBackupTarget.file(
    p.join(
      (await getTemporaryDirectory()).path,
      FullBackupService.exportFileName(DateTime.now()),
    ),
  );

  static Future<FullBackupSource?> pickSource() async {
    final path = await _files.invokeMethod<String>('pickZip');
    if (path == null) return null;
    _pickedZip = path;
    return FullBackupSource.file(path);
  }

  /// Lets the user choose where the finished zip goes and moves it there.
  /// False when they cancel; the file then stays where it was.
  static Future<bool> saveElsewhere(String path) async =>
      await _files.invokeMethod<bool>('exportFile', path) ?? false;

  static Future<int?> freeBytes() => _files.invokeMethod<int>('freeBytes');

  /// Deletes what a finished job left in the temp folder: the picked zip
  /// copy, and an export the user chose not to save.
  static Future<void> cleanUp({String? exportedZip}) async {
    for (final path in [_pickedZip, exportedZip]) {
      if (path == null) continue;
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    _pickedZip = null;
  }
}
