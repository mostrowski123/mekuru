import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/platform/full_backup_job_api.dart';
import 'package:mekuru/features/backup/data/models/full_backup_endpoints.dart';
import 'package:mekuru/features/backup/data/services/full_backup_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shared/full_backup_it_support.dart';
import 'test_helpers.dart';

/// The foreground service really runs, shows its progress notification
/// wherever the app may post one (`flutter test` reinstalls the app per
/// suite, so CI cannot pre-grant POST_NOTIFICATIONS; locally grant it with
/// `adb shell pm grant moe.matthew.mekuru android.permission.POST_NOTIFICATIONS`
/// while the suite runs to exercise the strict case), and goes away when the
/// job ends; a second job is refused while one exists.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// `FullBackupJobService.NOTIFICATION_ID`.
  const notificationId = 7401;

  late Directory root;
  late Directory tempDir;
  late AppDatabase db;
  late String zipPath;

  setUp(() async {
    root = await getApplicationSupportDirectory();
    tempDir = await Directory.systemTemp.createTemp('full_backup_svc_');
    zipPath = p.join(tempDir.path, 'mekuru-full-backup.zip');
    SharedPreferences.setMockInitialValues({});
    await wipeFullBackupState(root);
    await cleanupAppBooksDir();
    db = AppDatabase();
    await seedBigManga(db, root, files: 12, sizeBytes: 4 << 20);
  });

  tearDown(() async {
    await db.close();
    await wipeFullBackupState(root);
    await cleanupAppBooksDir();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  testWidgets(
    'the service and its notification exist exactly while the job runs',
    (tester) async {
      final notificationsEnabled = await fullBackupJobs.notificationsEnabled();
      expect(await fullBackupJobs.isServiceRunning(), isFalse);
      expect(
        await fullBackupJobs.activeNotificationIds(),
        isNot(contains(notificationId)),
      );

      await realFullBackupService(
        db,
        root,
      ).prepareExport(FullBackupTarget.file(zipPath));

      var sawService = false;
      var sawNotification = false;
      var lastDone = -1;
      var monotonic = true;
      FullBackupJobStatus status;
      final deadline = DateTime.now().add(const Duration(seconds: 90));
      do {
        if (await fullBackupJobs.isServiceRunning()) sawService = true;
        if ((await fullBackupJobs.activeNotificationIds()).contains(
          notificationId,
        )) {
          sawNotification = true;
        }
        status = await fullBackupJobs.status();
        if (status.lifecycle == FullBackupJobLifecycle.running) {
          if (status.done < lastDone) monotonic = false;
          lastDone = status.done;
          expect(status.total, greaterThan(0));
        }
        if (DateTime.now().isAfter(deadline)) fail('export never finished');
        await Future<void>.delayed(const Duration(milliseconds: 20));
      } while (!status.isTerminal);

      expect(status.lifecycle, FullBackupJobLifecycle.done);
      expect(sawService, isTrue, reason: 'the foreground service never ran');
      // ignore: avoid_print
      print('[lifecycle] notifications enabled: $notificationsEnabled');
      if (notificationsEnabled) {
        expect(sawNotification, isTrue, reason: 'no progress notification');
      }
      expect(monotonic, isTrue);
      expect(status.bytes, File(zipPath).lengthSync());

      // Gone once the job ended; the completion notice is only posted when
      // the activity is not in front, and the test activity is.
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(await fullBackupJobs.isServiceRunning(), isFalse);
      expect(
        await fullBackupJobs.activeNotificationIds(),
        isNot(contains(notificationId)),
      );
    },
  );

  testWidgets('a second job is refused while one is waiting to resume', (
    tester,
  ) async {
    await fullBackupJobs.abortForTest(afterBytes: 4 << 20);
    await realFullBackupService(
      db,
      root,
    ).prepareExport(FullBackupTarget.file(zipPath));
    await waitForJob(jobIsPaused, what: 'export to pause');

    await expectLater(
      fullBackupJobs.commitJob({
        'kind': 'export',
        'displayName': 'other.zip',
        'targetPath': p.join(tempDir.path, 'other.zip'),
        'totalBytes': 1,
      }),
      throwsA(isA<FullBackupJobBusyException>()),
    );
    await expectLater(
      realFullBackupService(
        db,
        root,
      ).prepareExport(FullBackupTarget.file(p.join(tempDir.path, 'other.zip'))),
      throwsA(isA<FullBackupBusyException>()),
    );
    expect(
      File(p.join(tempDir.path, 'other.zip.partial')).existsSync(),
      isFalse,
    );
  });
}
