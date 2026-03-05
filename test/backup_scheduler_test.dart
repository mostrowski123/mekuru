import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/backup/data/services/backup_scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('BackupScheduler.isBackupDue', () {
    test('returns false when interval is off', () async {
      SharedPreferences.setMockInitialValues({'backup.auto_interval': 'off'});

      final scheduler = BackupScheduler();
      expect(await scheduler.isBackupDue(), isFalse);
    });

    test('returns true when never backed up and interval is daily', () async {
      SharedPreferences.setMockInitialValues({
        'backup.auto_interval': 'daily',
        // no last_auto_at key
      });

      final scheduler = BackupScheduler();
      expect(await scheduler.isBackupDue(), isTrue);
    });

    test(
      'returns false when backed up 1 hour ago and interval is daily',
      () async {
        final oneHourAgo = DateTime.now().subtract(const Duration(hours: 1));
        SharedPreferences.setMockInitialValues({
          'backup.auto_interval': 'daily',
          'backup.last_auto_at': oneHourAgo.toUtc().toIso8601String(),
        });

        final scheduler = BackupScheduler();
        expect(await scheduler.isBackupDue(), isFalse);
      },
    );

    test(
      'returns true when backed up 25 hours ago and interval is daily',
      () async {
        final twentyFiveHoursAgo = DateTime.now().subtract(
          const Duration(hours: 25),
        );
        SharedPreferences.setMockInitialValues({
          'backup.auto_interval': 'daily',
          'backup.last_auto_at': twentyFiveHoursAgo.toUtc().toIso8601String(),
        });

        final scheduler = BackupScheduler();
        expect(await scheduler.isBackupDue(), isTrue);
      },
    );

    test(
      'returns true when backed up 8 days ago and interval is weekly',
      () async {
        final eightDaysAgo = DateTime.now().subtract(const Duration(days: 8));
        SharedPreferences.setMockInitialValues({
          'backup.auto_interval': 'weekly',
          'backup.last_auto_at': eightDaysAgo.toUtc().toIso8601String(),
        });

        final scheduler = BackupScheduler();
        expect(await scheduler.isBackupDue(), isTrue);
      },
    );

    test(
      'returns false when backed up 3 days ago and interval is weekly',
      () async {
        final threeDaysAgo = DateTime.now().subtract(const Duration(days: 3));
        SharedPreferences.setMockInitialValues({
          'backup.auto_interval': 'weekly',
          'backup.last_auto_at': threeDaysAgo.toUtc().toIso8601String(),
        });

        final scheduler = BackupScheduler();
        expect(await scheduler.isBackupDue(), isFalse);
      },
    );

    test('returns false when no interval is set (defaults to off)', () async {
      SharedPreferences.setMockInitialValues({});

      final scheduler = BackupScheduler();
      expect(await scheduler.isBackupDue(), isFalse);
    });
  });

  group('BackupScheduler.recordAutoBackup', () {
    test('stores the current timestamp', () async {
      SharedPreferences.setMockInitialValues({});

      final scheduler = BackupScheduler();
      await scheduler.recordAutoBackup();

      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString('backup.last_auto_at');
      expect(stored, isNotNull);

      final parsed = DateTime.parse(stored!);
      final diff = DateTime.now().difference(parsed);
      expect(diff.inSeconds, lessThan(5));
    });
  });

  group('BackupScheduler.setInterval / getInterval', () {
    test('round-trips interval setting', () async {
      SharedPreferences.setMockInitialValues({});

      final scheduler = BackupScheduler();

      await scheduler.setInterval(BackupInterval.daily);
      expect(await scheduler.getInterval(), BackupInterval.daily);

      await scheduler.setInterval(BackupInterval.weekly);
      expect(await scheduler.getInterval(), BackupInterval.weekly);

      await scheduler.setInterval(BackupInterval.off);
      expect(await scheduler.getInterval(), BackupInterval.off);
    });
  });

  group('BackupScheduler.getIntervalFromString', () {
    test('parses known values', () {
      expect(
        BackupScheduler.getIntervalFromString('daily'),
        BackupInterval.daily,
      );
      expect(
        BackupScheduler.getIntervalFromString('weekly'),
        BackupInterval.weekly,
      );
      expect(BackupScheduler.getIntervalFromString('off'), BackupInterval.off);
    });

    test('returns off for null or unknown values', () {
      expect(BackupScheduler.getIntervalFromString(null), BackupInterval.off);
      expect(
        BackupScheduler.getIntervalFromString('unknown'),
        BackupInterval.off,
      );
    });
  });
}
