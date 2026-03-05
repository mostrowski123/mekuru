import 'package:shared_preferences/shared_preferences.dart';

/// Auto-backup interval options.
enum BackupInterval { off, daily, weekly }

/// Checks if auto-backup is due at app startup.
class BackupScheduler {
  static const _intervalKey = 'backup.auto_interval';
  static const _lastAutoKey = 'backup.last_auto_at';

  /// Check if auto-backup is due based on configured interval and last backup.
  Future<bool> isBackupDue() async {
    final prefs = await SharedPreferences.getInstance();
    final interval = getIntervalFromString(prefs.getString(_intervalKey));
    if (interval == BackupInterval.off) return false;

    final lastAutoStr = prefs.getString(_lastAutoKey);
    if (lastAutoStr == null) return true; // never backed up

    final lastAuto = DateTime.tryParse(lastAutoStr);
    if (lastAuto == null) return true;

    final elapsed = DateTime.now().difference(lastAuto);
    return switch (interval) {
      BackupInterval.daily => elapsed.inHours >= 24,
      BackupInterval.weekly => elapsed.inDays >= 7,
      BackupInterval.off => false,
    };
  }

  /// Record that an auto-backup was just performed.
  Future<void> recordAutoBackup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _lastAutoKey,
      DateTime.now().toUtc().toIso8601String(),
    );
  }

  /// Get the currently configured interval.
  Future<BackupInterval> getInterval() async {
    final prefs = await SharedPreferences.getInstance();
    return getIntervalFromString(prefs.getString(_intervalKey));
  }

  /// Set the auto-backup interval.
  Future<void> setInterval(BackupInterval interval) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_intervalKey, interval.name);
  }

  /// Get the timestamp of the last auto-backup, or null if never performed.
  Future<DateTime?> getLastAutoBackupTime() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_lastAutoKey);
    if (str == null) return null;
    return DateTime.tryParse(str);
  }

  static BackupInterval getIntervalFromString(String? value) => switch (value) {
    'daily' => BackupInterval.daily,
    'weekly' => BackupInterval.weekly,
    _ => BackupInterval.off,
  };

  static String intervalLabel(BackupInterval interval) => switch (interval) {
    BackupInterval.off => 'Off',
    BackupInterval.daily => 'Daily',
    BackupInterval.weekly => 'Weekly',
  };
}
