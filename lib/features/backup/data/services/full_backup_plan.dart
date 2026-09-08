import 'dart:convert';
import 'dart:io';

import 'package:mekuru/features/backup/data/models/full_backup_manifest.dart';
import 'package:mekuru/features/backup/data/models/zip_folder_name.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// One archive entry: a source file, its name in the zip, and deflate level.
class FullBackupPlanEntry {
  final String path;
  final String name;
  final int size;
  final int level;

  const FullBackupPlanEntry({
    required this.path,
    required this.name,
    required this.size,
    required this.level,
  });

  /// The `plan.jsonl` line the Kotlin job reads (`PlanEntry` there).
  String toJsonLine() =>
      jsonEncode({'p': path, 'n': name, 's': size, 'l': level});
}

/// The book payload of an export, decided once and frozen in `plan.jsonl`.
class FullBackupPlan {
  final List<FullBackupPlanEntry> entries;

  /// Zip folder prefix (with trailing slash) → import directory name.
  final Map<String, String> folders;
  final int bookCount;
  final int dictionaryCount;
  final int externalMangaCount;

  const FullBackupPlan({
    required this.entries,
    required this.folders,
    required this.bookCount,
    required this.dictionaryCount,
    required this.externalMangaCount,
  });

  int get booksBytes => entries.fold(0, (sum, e) => sum + e.size);
}

/// Plain strings so the builder can run under `Isolate.run`.
class BuildExportPlanArgs {
  final String snapshotDbPath;
  final String booksDirPath;

  const BuildExportPlanArgs({
    required this.snapshotDbPath,
    required this.booksDirPath,
  });
}

/// Decides which files under `books/` ship and under which human-readable
/// names, from the database snapshot the export just took:
///
/// - every directory a row claims (`books/<dir>` segment of `file_path` or
///   `cover_image_path`, the same rule as `BookRepository.claimedDirNames`)
///   goes under `Books/<Title>/` or `Manga/<Title>/`, contents as on disk;
/// - loose files in the `books/` root (manga custom covers) go under
///   `Mekuru data/covers/`;
/// - orphan directories, `.trash` and `*.tmp` never ship.
///
/// Payload is stored (level 0): EPUB and image files are already compressed.
FullBackupPlan buildExportPlan(BuildExportPlanArgs args) {
  final booksDir = Directory(args.booksDirPath);
  final claims = <String, ({String section, String title})>{};
  int bookCount;
  int dictionaryCount;
  int externalMangaCount;

  final db = sqlite3.open(args.snapshotDbPath, mode: OpenMode.readOnly);
  try {
    final rows = db.select(
      'SELECT title, file_path, cover_image_path, book_type '
      'FROM books ORDER BY id',
    );
    bookCount = rows.length;
    externalMangaCount = 0;
    for (final row in rows) {
      final cover = row['cover_image_path'] as String?;
      if (cover != null && cover.startsWith('content://')) {
        externalMangaCount++;
      }
      final section = row['book_type'] == 'manga'
          ? FullBackupManifest.mangaPrefix
          : FullBackupManifest.booksPrefix;
      final title = (row['title'] as String?) ?? '';
      for (final path in [row['file_path'] as String?, cover]) {
        if (path == null || path.startsWith('content://')) continue;
        for (final dir in BookRepository.claimedDirNames(path)) {
          claims.putIfAbsent(dir, () => (section: section, title: title));
        }
      }
    }
    dictionaryCount =
        db
                .select(
                  'SELECT count(*) AS n FROM dictionary_metas WHERE is_hidden = 0',
                )
                .first['n']
            as int;
  } finally {
    db.close();
  }

  // Titles are made unique per section, case-insensitively, so two books
  // with the same name never merge into one folder.
  final folders = <String, String>{};
  for (final section in [
    FullBackupManifest.booksPrefix,
    FullBackupManifest.mangaPrefix,
  ]) {
    final dirs = claims.entries
        .where((e) => e.value.section == section)
        .map((e) => e.key)
        .toList();
    final names = dedupeFolderNames(
      dirs.map((dir) => zipFolderName(claims[dir]!.title, fallback: dir)),
    );
    for (var i = 0; i < dirs.length; i++) {
      folders['$section${names[i]}/'] = dirs[i];
    }
  }

  final entries = <FullBackupPlanEntry>[];
  void add(File file, String name) {
    entries.add(
      FullBackupPlanEntry(
        path: file.path,
        name: name,
        size: file.lengthSync(),
        level: 0,
      ),
    );
  }

  if (booksDir.existsSync()) {
    for (final entity in booksDir.listSync(followLinks: false)..sort(_byPath)) {
      if (entity is File && !entity.path.endsWith('.tmp')) {
        add(
          entity,
          '${FullBackupManifest.coversPrefix}${p.basename(entity.path)}',
        );
      }
    }
    for (final MapEntry(key: prefix, value: dir) in folders.entries) {
      final root = Directory(p.join(booksDir.path, dir));
      if (!root.existsSync()) continue;
      final files =
          root
              .listSync(recursive: true, followLinks: false)
              .whereType<File>()
              .where((f) => !f.path.endsWith('.tmp'))
              .toList()
            ..sort(_byPath);
      for (final file in files) {
        final relative = p.relative(file.path, from: root.path);
        add(file, prefix + p.split(relative).join('/'));
      }
    }
  }

  return FullBackupPlan(
    entries: entries,
    folders: folders,
    bookCount: bookCount,
    dictionaryCount: dictionaryCount,
    externalMangaCount: externalMangaCount,
  );
}

int _byPath(FileSystemEntity a, FileSystemEntity b) => a.path.compareTo(b.path);

/// The `README.txt` at the root of every archive. English only: it lives
/// in a file the user opens on a desktop, next to `manifest.json`.
String fullBackupReadme({
  required String appVersion,
  required DateTime createdAt,
}) {
  final date = createdAt.toUtc().toIso8601String().substring(0, 10);
  return '''
Mekuru full backup
==================
Created $date with Mekuru $appVersion.

What is in this file
--------------------
Books/         Your EPUB books, one folder per title. Each folder holds the
               original .epub file and the unpacked copy Mekuru reads from.
Manga/         Your manga, one folder per title: the page images and the
               page data Mekuru builds for them.
Mekuru data/   Mekuru's own files. mekuru_db.sqlite holds your dictionaries,
               reading progress, vocabulary, statistics and collections;
               settings.mekuru holds the app settings; covers/ holds custom
               covers.
manifest.json  A summary of this backup that Mekuru checks before restoring.

How to restore
--------------
Open Mekuru > Settings > Backup & Restore > Restore full backup (.zip) and
choose this file. Restoring replaces everything in Mekuru on that device
with the contents of this backup. Nothing outside Mekuru is touched.

Please do not rename, move or edit the files inside this archive if you plan
to restore it. Copying individual books out of it is fine.

Manga linked from folders outside Mekuru are not included; their pages stay
in the original folder.
''';
}
