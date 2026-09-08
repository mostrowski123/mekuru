import 'dart:convert';
import 'dart:io';

import 'package:mekuru/features/backup/data/models/full_backup_manifest.dart';
import 'package:mekuru/features/backup/data/models/zip_folder_name.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/settings/data/services/enhanced_furigana_dict_download_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// One archive entry: a source, its name in the zip, deflate level and
/// modification time (milliseconds since the epoch). [path] is a file path,
/// or the `content://` document of a page inside a folder the user linked.
class FullBackupPlanEntry {
  final String path;
  final String name;
  final int size;
  final int level;
  final int mtime;

  const FullBackupPlanEntry({
    required this.path,
    required this.name,
    required this.size,
    required this.level,
    required this.mtime,
  });

  /// The `plan.jsonl` line the Kotlin job reads (`PlanEntry` there).
  String toJsonLine() =>
      jsonEncode({'p': path, 'n': name, 's': size, 'l': level, 'm': mtime});
}

/// A manga whose pages live in a folder the user linked from outside Mekuru.
///
/// The plan only names the folder: listing it needs the platform channel,
/// which the isolate the plan is built in cannot reach, so the service lists
/// it and appends the pages under `<prefix>pages/`.
class LinkedMangaSource {
  final String prefix;
  final String treeUri;
  final String imageDirRelativePath;

  const LinkedMangaSource({
    required this.prefix,
    required this.treeUri,
    required this.imageDirRelativePath,
  });
}

/// The payload of an export, decided once and frozen in `plan.jsonl`.
class FullBackupPlan {
  final List<FullBackupPlanEntry> entries;

  /// Zip folder prefix (with trailing slash) → import directory name.
  final Map<String, String> folders;
  final List<LinkedMangaSource> linkedManga;
  final int bookCount;
  final int dictionaryCount;

  const FullBackupPlan({
    required this.entries,
    required this.folders,
    required this.linkedManga,
    required this.bookCount,
    required this.dictionaryCount,
  });
}

/// Plain strings so the builder can run under `Isolate.run`.
class BuildExportPlanArgs {
  final String snapshotDbPath;
  final String booksDirPath;

  /// The UniDic-lite directory; shipped only when its install marker is
  /// there. Null when the caller has no documents directory.
  final String? unidicDirPath;

  const BuildExportPlanArgs({
    required this.snapshotDbPath,
    required this.booksDirPath,
    this.unidicDirPath,
  });
}

/// Decides which local files ship and under which human-readable names, from
/// the database snapshot the export just took:
///
/// - every directory a row claims (`books/<dir>` segment of `file_path` or
///   `cover_image_path`, the same rule as `BookRepository.claimedDirNames`)
///   goes under `Books/<Title>/` or `Manga/<Title>/`, contents as on disk;
/// - loose files in the `books/` root (manga custom covers) go under
///   `Mekuru data/covers/`;
/// - the UniDic-lite directory, when installed, goes under
///   `Mekuru data/unidic-lite/`;
/// - orphan directories, `.trash` and `*.tmp` never ship.
///
/// Manga whose pages live in a linked folder are reported in
/// [FullBackupPlan.linkedManga] for the service to list.
///
/// Payload is stored (level 0): EPUB, image and dictionary files gain little
/// from deflate and a multi-gigabyte export should be bound by I/O.
FullBackupPlan buildExportPlan(BuildExportPlanArgs args) {
  final booksDir = Directory(args.booksDirPath);
  final claims = <String, ({String section, String title})>{};
  int bookCount;
  int dictionaryCount;

  final db = sqlite3.open(args.snapshotDbPath, mode: OpenMode.readOnly);
  try {
    final rows = db.select(
      'SELECT title, file_path, cover_image_path, book_type '
      'FROM books ORDER BY id',
    );
    bookCount = rows.length;
    for (final row in rows) {
      final section = row['book_type'] == 'manga'
          ? FullBackupManifest.mangaPrefix
          : FullBackupManifest.booksPrefix;
      final title = (row['title'] as String?) ?? '';
      for (final path in [
        row['file_path'] as String?,
        row['cover_image_path'] as String?,
      ]) {
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
  final linked = <LinkedMangaSource>[];
  void add(File file, String name) {
    final stat = file.statSync();
    entries.add(
      FullBackupPlanEntry(
        path: file.path,
        name: name,
        size: stat.size,
        level: 0,
        mtime: stat.modified.millisecondsSinceEpoch,
      ),
    );
  }

  void addTree(Directory root, String prefix) {
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
      addTree(root, prefix);
      if (prefix.startsWith(FullBackupManifest.mangaPrefix)) {
        final folder = _linkedFolder(
          File(p.join(root.path, mangaPagesCacheFileName)),
        );
        if (folder != null) {
          linked.add(
            LinkedMangaSource(
              prefix: prefix,
              treeUri: folder.treeUri,
              imageDirRelativePath: folder.imageDir,
            ),
          );
        }
      }
    }
  }

  final unidicDirPath = args.unidicDirPath;
  if (unidicDirPath != null &&
      EnhancedFuriganaDictDownloadService.isInstalledAt(unidicDirPath)) {
    addTree(Directory(unidicDirPath), FullBackupManifest.unidicPrefix);
  }

  return FullBackupPlan(
    entries: entries,
    folders: folders,
    linkedManga: linked,
    bookCount: bookCount,
    dictionaryCount: dictionaryCount,
  );
}

int _byPath(FileSystemEntity a, FileSystemEntity b) => a.path.compareTo(b.path);

/// The folder a manga reads its pages from when it was linked rather than
/// imported, or null (also for a cache that cannot be read: the manga still
/// ships, without pages).
///
/// ponytail: decodes every manga cache (megabytes each) once per export; if
/// "Preparing…" grows long on big libraries, record the link on the books
/// row at import time and read it from the snapshot instead.
({String treeUri, String imageDir})? _linkedFolder(File cache) {
  if (!cache.existsSync()) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(cache.readAsStringSync());
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  final treeUri = decoded['safTreeUri'];
  final imageDir = decoded['safImageDirRelativePath'];
  if (treeUri is! String || imageDir is! String) return null;
  return (treeUri: treeUri, imageDir: imageDir);
}

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
               page data Mekuru builds for them. For manga you linked from a
               folder outside Mekuru, the pages were copied in under pages/.
Mekuru data/   Mekuru's own files. mekuru_db.sqlite holds your dictionaries,
               reading progress, vocabulary, statistics and collections;
               settings.mekuru holds the app settings; covers/ holds custom
               covers; unidic-lite/ is the downloaded UniDic-lite dictionary,
               present only if you had installed it.
manifest.json  A summary of this backup that Mekuru checks before restoring.

How to restore
--------------
Open Mekuru > Settings > Backup & Restore > Restore full backup (.zip) and
choose this file. Restoring replaces everything in Mekuru on that device
with the contents of this backup. Nothing outside Mekuru is touched. Manga
that were linked from a folder outside Mekuru come back stored inside Mekuru.

Please do not rename, move or edit the files inside this archive if you plan
to restore it. Copying individual books out of it is fine.
''';
}
