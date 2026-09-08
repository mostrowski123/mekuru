import 'dart:io';

import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/platform/android_saf_service.dart';
import 'package:mekuru/core/platform/full_backup_job_api.dart';
import 'package:mekuru/features/backup/data/services/backup_service.dart';
import 'package:mekuru/features/backup/data/services/book_match_service.dart';
import 'package:mekuru/features/backup/data/services/full_backup_service.dart';
import 'package:mekuru/features/backup/data/services/staged_full_restore.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:path/path.dart' as p;

/// Helpers shared by the full-backup emulator suites: they drive the REAL
/// native job service through the real method channel, with plain files
/// standing in for the SAF pickers.
const fullBackupJobs = FullBackupJobChannel();

FullBackupService realFullBackupService(
  AppDatabase db,
  Directory root, {
  Directory? documentsRoot,
  Future<List<SafTreeFile>> Function(String treeUri, String relativePath)?
  listTreeFiles,
}) => FullBackupService(
  db: db,
  backupService: BackupService(db, BookMatchService()),
  root: root,
  documentsRoot: documentsRoot,
  appVersion: 'integration',
  listTreeFiles: listTreeFiles ?? AndroidSafService.listFilesInTreeDir,
);

/// A small valid PNG: the library decodes covers once the app shows, so
/// fixtures must be real images.
Uint8List tinyPng() => img.encodePng(
  img.Image(width: 8, height: 8)..clear(img.ColorRgb8(200, 80, 80)),
);

/// Polls the native job until [until] holds.
Future<FullBackupJobStatus> waitForJob(
  bool Function(FullBackupJobStatus status) until, {
  Duration timeout = const Duration(seconds: 120),
  String what = 'job',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    final status = await fullBackupJobs.status();
    if (until(status)) return status;
    if (DateTime.now().isAfter(deadline)) {
      fail(
        'Timed out waiting for $what; last status: ${status.lifecycle.name} '
        '${status.phase} ${status.done}/${status.total} ${status.error}',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

bool jobIsTerminal(FullBackupJobStatus s) => s.isTerminal;
bool jobIsPaused(FullBackupJobStatus s) =>
    s.lifecycle == FullBackupJobLifecycle.paused;
bool jobIsDone(FullBackupJobStatus s) =>
    s.lifecycle == FullBackupJobLifecycle.done;

/// Cancels whatever job a previous test left behind and removes every
/// trace of jobs and staged restores under [root].
Future<void> wipeFullBackupState(Directory root) async {
  var status = await fullBackupJobs.status();
  if (status.isActive) {
    await fullBackupJobs.cancel();
    status = await waitForJob(
      (s) => !s.isActive,
      timeout: const Duration(seconds: 30),
      what: 'cancel of a leftover job',
    );
  }
  await fullBackupJobs.consumeResult();
  for (final name in [
    StagedFullRestore.jobDirName,
    StagedFullRestore.stagingDirName,
    StagedFullRestore.rollbackDirName,
  ]) {
    final dir = Directory(p.join(root.path, name));
    if (await dir.exists()) await dir.delete(recursive: true);
  }
  await for (final entity in root.list()) {
    if (entity.path.endsWith(StagedFullRestore.tombstoneSuffix)) {
      await entity.delete(recursive: true);
    }
  }
}

/// A manga big enough that a job takes a measurable time: [files] real PNG
/// pages of at least [sizeBytes] each in a fresh import dir, referenced by a
/// row. Real images, because the library renders them once the app shows:
/// noise stored without compression keeps them large.
Future<Directory> seedBigManga(
  AppDatabase db,
  Directory root, {
  int files = 8,
  int sizeBytes = 4 << 20,
  String title = '大きい漫画',
}) async {
  final dirName = BookRepository.uniqueImportDirName('manga');
  final dir = Directory(p.join(root.path, BookRepository.booksSegment, dirName))
    ..createSync(recursive: true);
  final side = math.sqrt(sizeBytes / 3).ceil() + 8;
  final noise = img.Image(width: side, height: side);
  final random = math.Random(42);
  for (final pixel in noise) {
    pixel.setRgb(random.nextInt(256), random.nextInt(256), random.nextInt(256));
  }
  final png = img.encodePng(noise, level: 0);
  expect(png.length, greaterThanOrEqualTo(sizeBytes));
  for (var f = 0; f < files; f++) {
    File(
      p.join(dir.path, '${(f + 1).toString().padLeft(3, '0')}.png'),
    ).writeAsBytesSync(png);
  }
  File(p.join(dir.path, 'pages_cache.json')).writeAsStringSync('{}');
  await db
      .into(db.books)
      .insert(
        BooksCompanion.insert(
          title: title,
          filePath: dir.path,
          bookType: const Value('manga'),
        ),
      );
  return dir;
}

/// Reads every file entry of [zipPath] with `package:archive`, an
/// implementation independent of the java.util.zip family the writer
/// mirrors, verifying each CRC. Returns entry name → bytes.
Future<Map<String, Uint8List>> readZipWithArchive(String zipPath) async {
  final input = InputFileStream(zipPath);
  try {
    final archive = ZipDecoder().decodeStream(input, verify: true);
    final out = <String, Uint8List>{};
    for (final file in archive) {
      if (!file.isFile) continue;
      out[file.name] = Uint8List.fromList(file.content as List<int>);
      file.clear();
    }
    return out;
  } finally {
    await input.close();
  }
}

/// Every file under `books/<dir>` as archive-relative paths → bytes.
Map<String, Uint8List> filesUnder(Directory dir) {
  final out = <String, Uint8List>{};
  for (final entity in dir.listSync(recursive: true, followLinks: false)) {
    if (entity is File) {
      out[p.split(p.relative(entity.path, from: dir.path)).join('/')] = entity
          .readAsBytesSync();
    }
  }
  return out;
}
