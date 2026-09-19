import 'dart:io';

import 'package:flutter/services.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';

const _channel = MethodChannel('mekuru/ios_storage');

/// Marks [dirs] (and everything under them) as excluded from iCloud and
/// device backups. App Review rejects apps that back up data the app can
/// download or regenerate, which is what lives in these directories.
///
/// The flag sits on the directory itself, so call this again after a
/// directory was deleted and recreated. iOS only, skips missing directories,
/// and never throws: a failure here must not block a launch or a download.
Future<void> excludeFromIosBackup(Iterable<String> dirs) async {
  if (!Platform.isIOS) return;
  final existing = [
    for (final dir in dirs)
      if (Directory(dir).existsSync()) dir,
  ];
  if (existing.isEmpty) return;
  try {
    await _channel.invokeMethod<void>('excludeFromBackup', existing);
  } catch (e, st) {
    logFailure('ios.exclude_from_backup_failed', e, stackTrace: st);
  }
}
