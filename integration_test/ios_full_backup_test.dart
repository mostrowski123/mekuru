import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/core/platform/full_backup_job_api.dart';
import 'package:mekuru/features/backup/data/models/full_backup_manifest.dart';
import 'package:mekuru/features/backup/data/services/dart_full_backup_job.dart';
import 'package:mekuru/features/backup/data/services/full_backup_service.dart';
import 'package:mekuru/features/backup/data/services/ios_full_backup.dart';
import 'package:mekuru/features/backup/data/services/staged_full_restore.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// iOS only: the in-process full-backup job on a real app container. It works
/// in its own folder with its own staging path, never the app's
/// `restore_staging/`, so nothing here can be applied at the next launch.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'exports a library to a zip and restores it into a staging folder',
    skip: !Platform.isIOS,
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final outcome = await tester.runAsync(() async {
        final root = await Directory(
          p.join(
            (await getApplicationSupportDirectory()).path,
            'full_backup_it_${DateTime.now().microsecondsSinceEpoch}',
          ),
        ).create();
        try {
          final random = Random(3);
          final sources = <String, List<int>>{
            FullBackupManifest.manifestEntry: utf8.encode(
              '{"formatVersion":1}',
            ),
            FullBackupManifest.databaseEntry: List.generate(
              400000,
              (i) => i % 251,
            ),
            'Books/日本語の本/0001.jpg': List.generate(
              300000,
              (_) => random.nextInt(256),
            ),
          };
          final jobDir = await Directory(
            p.join(root.path, StagedFullRestore.jobDirName),
          ).create();
          final plan = StringBuffer();
          var total = 0;
          for (final (i, e) in sources.entries.indexed) {
            final file = File(p.join(root.path, 'src_$i'))
              ..writeAsBytesSync(e.value);
            total += e.value.length;
            plan.writeln(
              jsonEncode({
                'p': file.path,
                'n': e.key,
                's': e.value.length,
                'l': e.key.endsWith('.jpg') ? 0 : 6,
                'm': 1700000000000,
              }),
            );
          }
          File(
            p.join(jobDir.path, FullBackupService.planFileName),
          ).writeAsStringSync(plan.toString());

          final job = DartFullBackupJob(root: root);
          final zip = p.join(root.path, 'out', 'backup.zip');
          await job.commitJob({
            'kind': 'export',
            'displayName': 'backup.zip',
            'targetPath': zip,
            'totalBytes': total,
          });
          await job.finished;
          final exported = await job.consumeResult();

          final peek = await job.inspectZip(
            uri: zip,
            name: FullBackupManifest.manifestEntry,
          );

          final staging = p.join(root.path, 'staging');
          await job.commitJob({
            'kind': 'restore',
            'sourceUri': zip,
            'stagingPath': staging,
            'totalBytes': File(zip).lengthSync(),
            // Zip folder -> directory under books/, as the manifest records it.
            'folders': {'Books/日本語の本/': 'book_1_test'},
            'manifestJson': '{"formatVersion":1}',
          });
          await job.finished;
          final restored = await job.consumeResult();

          return (
            exported: exported?.lifecycle,
            complete: peek?.complete,
            manifest: peek?.text,
            restored: restored?.lifecycle,
            error: restored?.error ?? exported?.error,
            page:
                File(
                  p.join(staging, 'books', 'book_1_test', '0001.jpg'),
                ).existsSync()
                ? File(
                    p.join(staging, 'books', 'book_1_test', '0001.jpg'),
                  ).lengthSync()
                : -1,
            marker: File(p.join(staging, 'EXTRACTED')).existsSync(),
            free: await IosFullBackup.freeBytes(),
          );
        } finally {
          await root.delete(recursive: true);
        }
      });

      // ignore: avoid_print
      print('full backup on iOS: $outcome');
      expect(outcome!.error, isNull);
      expect(outcome.exported, FullBackupJobLifecycle.done);
      expect(outcome.complete, isTrue);
      expect(outcome.manifest, '{"formatVersion":1}');
      expect(outcome.restored, FullBackupJobLifecycle.done);
      expect(outcome.page, 300000);
      expect(outcome.marker, isTrue);
      // The native free-space call answers with something plausible.
      expect(outcome.free, greaterThan(1000000));
    },
  );
}
