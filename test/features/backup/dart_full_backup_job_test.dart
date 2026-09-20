import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart'
    show ArchiveFile, CompressionType, ZipFileEncoder;
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/platform/full_backup_job_api.dart';
import 'package:mekuru/features/backup/data/services/dart_full_backup_job.dart';
import 'package:mekuru/features/backup/data/services/full_backup_plan.dart';
import 'package:mekuru/features/backup/data/services/full_backup_service.dart';
import 'package:mekuru/features/backup/data/services/staged_full_restore.dart';
import 'package:path/path.dart' as p;

import 'full_backup_zip_fixtures.dart';

/// The in-process (iOS) job against a real temp directory laid out like the
/// app-support root. The export and restore cases are the ones of the Kotlin
/// `ExportJobTest` and `RestoreJobTest` that do not depend on resuming.
void main() {
  late Directory tmp;
  late Directory root;
  late DartFullBackupJob job;

  Directory staging() =>
      Directory(p.join(root.path, StagedFullRestore.stagingDirName));
  File extracted() =>
      File(p.join(staging().path, StagedFullRestore.extractedMarkerName));
  List<String> tombstones() => [
    for (final entity in root.listSync())
      if (entity.path.endsWith(StagedFullRestore.tombstoneSuffix)) entity.path,
  ];

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('dart_full_backup_job_');
    root = Directory(p.join(tmp.path, 'support'))..createSync();
    job = DartFullBackupJob(root: root);
  });

  tearDown(() async {
    await job.finished;
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<FullBackupJobStatus> run(Map<String, Object?> spec) async {
    await job.commitJob(spec);
    await job.finished;
    return job.status();
  }

  // ──────────────── Export ────────────────

  const folders = {
    'Books/メロス/': 'book_1_abcdef12',
    'Manga/漫画/': 'manga_2_00000000',
  };

  /// Device path (relative to the root) → zip entry name and level. The
  /// sidecars sit in the job directory, as `FullBackupService` leaves them.
  const library = [
    ('full_backup_job/manifest.json', 'manifest.json', 6),
    ('full_backup_job/README.txt', 'README.txt', 6),
    ('full_backup_job/settings.mekuru', 'Mekuru data/settings.mekuru', 6),
    ('full_backup_job/mekuru_db.sqlite', 'Mekuru data/mekuru_db.sqlite', 6),
    ('books/custom_cover_9.jpg', 'Mekuru data/covers/custom_cover_9.jpg', 0),
    ('books/book_1_abcdef12/本.epub', 'Books/メロス/本.epub', 0),
    (
      'books/book_1_abcdef12/content/ch1.xhtml',
      'Books/メロス/content/ch1.xhtml',
      0,
    ),
    ('books/manga_2_00000000/001.jpg', 'Manga/漫画/001.jpg', 0),
    ('books/manga_2_00000000/pages_cache.json', 'Manga/漫画/pages_cache.json', 0),
  ];

  /// Seeds the library and its `plan.jsonl`; returns entry name → bytes.
  Map<String, List<int>> seedLibrary({int pageBytes = 90 * 1024}) {
    final contents = <String, List<int>>{};
    final lines = StringBuffer();
    for (final (index, (path, name, level)) in library.indexed) {
      final bytes = switch (name) {
        'manifest.json' => utf8.encode('{"format":1}'),
        'Mekuru data/mekuru_db.sqlite' => List.generate(
          300 * 1024,
          (i) => i % 7,
        ),
        'Manga/漫画/001.jpg' => randomBytes(index, pageBytes),
        'Manga/漫画/pages_cache.json' => <int>[],
        _ => randomBytes(index, 20 * 1024),
      };
      final file = File(p.join(root.path, path));
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes);
      contents[name] = bytes;
      lines.writeln(
        FullBackupPlanEntry(
          path: file.path,
          name: name,
          size: bytes.length,
          level: level,
          mtime: fixtureMtime,
        ).toJsonLine(),
      );
    }
    File(
      p.join(
        root.path,
        StagedFullRestore.jobDirName,
        FullBackupService.planFileName,
      ),
    ).writeAsStringSync(lines.toString());
    return contents;
  }

  File target() => File(p.join(tmp.path, 'out', 'mekuru-full-backup.zip'));

  Map<String, Object?> exportSpec(Map<String, List<int>> contents) => {
    'kind': 'export',
    'displayName': p.basename(target().path),
    'targetPath': target().path,
    'totalBytes': contents.values.fold<int>(0, (sum, b) => sum + b.length),
  };

  group('export', () {
    test('writes a complete archive, manifest first, and its result', () async {
      final contents = seedLibrary();
      final status = await run(exportSpec(contents));

      expect(status.lifecycle, FullBackupJobLifecycle.done);
      expect(status.kind, FullBackupJobKind.export);
      expect(status.location, target().path);
      expect(status.bytes, target().lengthSync());
      expect(status.entries, library.length);
      expect(status.skippedFiles, 0);
      expect(status.renamed, isTrue);

      final zip = readZip(target());
      expect(zip.keys.first, 'manifest.json');
      expect(zip.keys.toList(), library.map((e) => e.$2).toList());
      for (final MapEntry(key: name, value: bytes) in contents.entries) {
        expect(zip[name], bytes, reason: name);
      }
      expect(File('${target().path}.partial').existsSync(), isFalse);
      // The snapshot and the plan are gone with the job.
      expect(
        Directory(p.join(root.path, StagedFullRestore.jobDirName)).listSync(),
        isEmpty,
      );
      expect(await job.consumeResult(), status);
      expect(await job.status(), FullBackupJobStatus.none);
      expect(await job.consumeResult(), isNull);
    });

    test('a source file that vanished is skipped, not fatal', () async {
      final contents = seedLibrary();
      File(p.join(root.path, library[5].$1)).deleteSync();

      final status = await run(exportSpec(contents));

      expect(status.lifecycle, FullBackupJobLifecycle.done);
      expect(status.skippedFiles, 1);
      expect(status.entries, library.length - 1);
      final zip = readZip(target());
      expect(zip.containsKey(library[5].$2), isFalse);
      expect(zip[library[7].$2], contents[library[7].$2]);
    });

    test('a second commit while one runs is refused', () async {
      final spec = exportSpec(seedLibrary());
      await job.commitJob(spec);
      expect((await job.status()).lifecycle, FullBackupJobLifecycle.running);
      await expectLater(
        job.commitJob(spec),
        throwsA(isA<FullBackupJobBusyException>()),
      );
    });

    test('cancel mid-entry deletes the partial archive', () async {
      final spec = exportSpec(seedLibrary(pageBytes: 8 * 1024 * 1024));
      await job.commitJob(spec);
      var running = await job.status();
      while (running.isActive && running.done == 0) {
        await Future<void>.delayed(Duration.zero);
        running = await job.status();
      }
      expect(await job.cancel(), isTrue);
      await job.finished;

      final status = await job.status();
      expect(status.lifecycle, FullBackupJobLifecycle.cancelled);
      expect(status.kind, FullBackupJobKind.export);
      expect(target().parent.listSync(), isEmpty);
      expect(await job.cancel(), isFalse);
    });

    test('a partial left by a killed export does not survive', () async {
      final stale = File(p.join(target().parent.path, 'old.zip.partial'))
        ..createSync(recursive: true);
      final status = await run(exportSpec(seedLibrary()));
      expect(status.lifecycle, FullBackupJobLifecycle.done);
      expect(stale.existsSync(), isFalse);
    });

    test('a folder target has no in-process writer', () async {
      seedLibrary();
      final status = await run({'kind': 'export', 'treeUri': 'content://x'});
      expect(status.lifecycle, FullBackupJobLifecycle.failed);
      expect(status.error, 'target_unavailable');
    });
  });

  // ──────────────── Restore ────────────────

  final entries = <(String, List<int>)>[
    ('manifest.json', utf8.encode('{"format":1}')),
    ('README.txt', utf8.encode('hello')),
    ('Mekuru data/settings.mekuru', utf8.encode('{"version":1}')),
    ('Mekuru data/mekuru_db.sqlite', List.generate(200 * 1024, (i) => i % 3)),
    ('Mekuru data/covers/custom_cover_9.jpg', randomBytes(9, 30 * 1024)),
    ('Books/メロス/本.epub', randomBytes(1, 150 * 1024)),
    ('Books/メロス/content/ch1.xhtml', utf8.encode('<p>走れ</p>')),
    ('Manga/漫画/001.jpg', randomBytes(2, 120 * 1024)),
    ('Manga/漫画/pages_cache.json', utf8.encode('{}')),
    ('Unknown/stray.txt', utf8.encode('?')),
  ];

  const expectedFiles = {
    'mekuru_db.sqlite': 3,
    'settings.mekuru': 2,
    'books/custom_cover_9.jpg': 4,
    'books/book_1_abcdef12/本.epub': 5,
    'books/book_1_abcdef12/content/ch1.xhtml': 6,
    'books/manga_2_00000000/001.jpg': 7,
    'books/manga_2_00000000/pages_cache.json': 8,
  };

  const manifestJson = '{"format":1,"bookCount":2}';

  Map<String, Object?> restoreSpec(File archive) => {
    'kind': 'restore',
    'sourceUri': Uri.file(archive.path).toString(),
    'stagingPath': staging().path,
    'totalBytes': entries.fold<int>(0, (sum, e) => sum + e.$2.length),
    'folders': folders,
    'manifestJson': manifestJson,
  };

  void expectRestored() {
    for (final MapEntry(key: rel, value: index) in expectedFiles.entries) {
      final file = File(p.join(staging().path, rel));
      expect(file.existsSync(), isTrue, reason: 'missing $rel');
      expect(file.readAsBytesSync(), entries[index].$2, reason: rel);
    }
    expect(Directory(p.join(staging().path, 'Unknown')).existsSync(), isFalse);
    expect(File(p.join(staging().path, 'manifest.json')).existsSync(), isFalse);
    expect(extracted().readAsStringSync(), manifestJson);
  }

  group('restore', () {
    late File archive;

    setUp(() async {
      archive = await buildArchive(
        File(p.join(tmp.path, 'src', 'a.zip')),
        entries,
      );
    });

    test('extracts into the device layout and writes EXTRACTED', () async {
      final status = await run(restoreSpec(archive));

      expect(status.lifecycle, FullBackupJobLifecycle.done);
      expect(status.kind, FullBackupJobKind.restore);
      expectRestored();
      expect(StagedFullRestore.hasStagedRestore(root), isTrue);
    });

    test('reports progress while it runs', () async {
      await job.commitJob(restoreSpec(archive));
      final running = await job.status();
      expect(running.lifecycle, FullBackupJobLifecycle.running);
      expect(running.phase, 'extracting');
      expect(
        running.total,
        entries.fold<int>(0, (sum, e) => sum + e.$2.length),
      );
    });

    test('restores an archive another tool wrote, ZIP64 or not', () async {
      final foreign = p.join(tmp.path, 'src', 'foreign.zip');
      final encoder = ZipFileEncoder()..create(foreign);
      for (final (name, bytes) in entries) {
        encoder.addArchiveFile(
          ArchiveFile.bytes(name, bytes)
            ..compression = name.endsWith('.jpg')
                ? CompressionType.none
                : CompressionType.deflate,
        );
      }
      await encoder.close();
      expect(
        (await run(restoreSpec(File(foreign)))).lifecycle,
        FullBackupJobLifecycle.done,
      );
      expectRestored();
      await job.consumeResult();
      StagedFullRestore.retire(staging());

      final zip64 = await buildArchive(
        File(p.join(tmp.path, 'src', 'z64.zip')),
        entries,
        forceZip64: true,
      );
      // A plain path works as well as a `file:` URI.
      final status = await run({
        ...restoreSpec(zip64),
        'sourceUri': zip64.path,
      });
      expect(status.lifecycle, FullBackupJobLifecycle.done);
      expectRestored();
    });

    test('a second run after EXTRACTED is a no-op', () async {
      await run(restoreSpec(archive));
      final page = File(
        p.join(staging().path, 'books/manga_2_00000000/001.jpg'),
      )..deleteSync();

      final status = await run(restoreSpec(archive));

      expect(status.lifecycle, FullBackupJobLifecycle.done);
      expect(extracted().readAsStringSync(), manifestJson);
      expect(page.existsSync(), isFalse);
    });

    test('a corrupt entry fails before anything is committed', () async {
      corruptEntry(archive, 'Manga/漫画/001.jpg');

      final status = await run(restoreSpec(archive));

      expect(status.lifecycle, FullBackupJobLifecycle.failed);
      expect(status.kind, FullBackupJobKind.restore);
      expect(status.error, 'corrupt_archive');
      expect(staging().existsSync(), isFalse);
      expect(tombstones(), isEmpty);
    });

    test('an escaping entry is refused', () async {
      final evil = await buildArchive(File(p.join(tmp.path, 'evil', 'e.zip')), [
        ('Books/メロス/../../../evil.txt', utf8.encode('pwned')),
      ]);

      final status = await run(restoreSpec(evil));

      expect(status.lifecycle, FullBackupJobLifecycle.failed);
      expect(status.error, 'unsafe_archive');
      expect(
        tmp
            .listSync(recursive: true)
            .where((e) => p.basename(e.path) == 'evil.txt'),
        isEmpty,
      );
    });

    test('a truncated archive fails for good', () async {
      final bytes = archive.readAsBytesSync();
      archive.writeAsBytesSync(bytes.sublist(0, bytes.length ~/ 2));
      final status = await run(restoreSpec(archive));
      expect(status.error, 'corrupt_archive');
      expect(extracted().existsSync(), isFalse);
    });

    test('a missing source fails for good', () async {
      final status = await run(restoreSpec(File(p.join(tmp.path, 'gone.zip'))));
      expect(status.lifecycle, FullBackupJobLifecycle.failed);
      expect(status.error, 'source_missing');
    });

    test('cancel stops the extraction and retires the staging dir', () async {
      await job.commitJob(restoreSpec(archive));
      expect(await job.cancel(), isTrue);
      await job.finished;

      final status = await job.status();
      expect(status.lifecycle, FullBackupJobLifecycle.cancelled);
      expect(status.kind, FullBackupJobKind.restore);
      expect(staging().existsSync(), isFalse);
      expect(tombstones(), isEmpty);
    });

    test('what a killed restore left in staging is not mixed in', () async {
      final stale = File(p.join(staging().path, 'books', 'stale', 'x.jpg'))
        ..createSync(recursive: true);

      final status = await run(restoreSpec(archive));

      expect(status.lifecycle, FullBackupJobLifecycle.done);
      expect(stale.existsSync(), isFalse);
      expectRestored();
      expect(tombstones(), isEmpty);
    });
  });

  // ──────────────── Both ways ────────────────

  test('an exported library restores into the staged layout', () async {
    final contents = seedLibrary();
    expect(
      (await run(exportSpec(contents))).lifecycle,
      FullBackupJobLifecycle.done,
    );
    await job.consumeResult();

    final inspection = await job.inspectZip(
      uri: Uri.file(target().path).toString(),
      name: 'manifest.json',
    );
    expect(inspection!.isZip, isTrue);
    expect(inspection.text, '{"format":1}');
    expect(inspection.complete, isTrue);

    final status = await run({
      'kind': 'restore',
      'sourceUri': Uri.file(target().path).toString(),
      'stagingPath': staging().path,
      'totalBytes': 0,
      'folders': folders,
      'manifestJson': inspection.text,
    });

    expect(status.lifecycle, FullBackupJobLifecycle.done);
    final staged = {
      for (final entity in staging().listSync(recursive: true))
        if (entity is File)
          p.relative(entity.path, from: staging().path): entity
              .readAsBytesSync(),
    };
    expect(staged, {
      'EXTRACTED': utf8.encode('{"format":1}'),
      'settings.mekuru': contents['Mekuru data/settings.mekuru'],
      'mekuru_db.sqlite': contents['Mekuru data/mekuru_db.sqlite'],
      for (final (path, name, _) in library.skip(4)) path: contents[name],
    });
  });

  test('inspectZip tells a reading-data file from a zip', () async {
    final json = File(p.join(tmp.path, 'data.mekuru'))
      ..writeAsStringSync('{"version":1}');
    final inspection = await job.inspectZip(
      uri: json.path,
      name: 'manifest.json',
    );
    expect(inspection!.isZip, isFalse);
    expect(inspection.text, isNull);
    expect(await job.requestNotificationPermission(), isFalse);
  });

  test('recover clears what a killed job left behind', () async {
    seedLibrary();
    File(p.join(staging().path, 'books', 'x.jpg')).createSync(recursive: true);
    Directory(
      p.join(
        root.path,
        'restore_rollback.1${StagedFullRestore.tombstoneSuffix}',
      ),
    ).createSync();

    await job.recover();

    expect(
      Directory(p.join(root.path, StagedFullRestore.jobDirName)).listSync(),
      isEmpty,
    );
    expect(staging().existsSync(), isFalse);
    expect(tombstones(), isEmpty);
    expect(Directory(p.join(root.path, 'books')).existsSync(), isTrue);
  });

  test('recover leaves a staged restore to the boot hook', () async {
    final archive = await buildArchive(
      File(p.join(tmp.path, 'src', 'a.zip')),
      entries,
    );
    await run(restoreSpec(archive));
    await job.recover();
    expectRestored();
  });
}
