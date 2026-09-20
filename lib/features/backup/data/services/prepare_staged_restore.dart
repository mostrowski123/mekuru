import 'dart:convert';
import 'dart:io';

import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/utils/atomic_file.dart';
import 'package:mekuru/features/backup/data/models/full_backup_manifest.dart';
import 'package:mekuru/features/backup/data/services/backup_serializer.dart';
import 'package:mekuru/features/backup/data/services/staged_full_restore.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/data/services/cbz_parser.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// Arguments for [prepareStagedRestore]; plain strings so it can run under
/// `compute()`.
class PrepareStagedRestoreArgs {
  final String stagingPath;
  final String rootPath;
  final String manifestJson;

  /// Whether a manga whose pages the archive does not carry may stay linked
  /// to its folder outside Mekuru. Only Android can follow such a link (a
  /// `content://` URI); anywhere else it is cut, see [prepareStagedRestore].
  final bool keepFolderLinks;

  PrepareStagedRestoreArgs({
    required this.stagingPath,
    required this.rootPath,
    required this.manifestJson,
    bool? keepFolderLinks,
  }) : keepFolderLinks = keepFolderLinks ?? Platform.isAndroid;
}

class PreparedStagedRestore {
  /// Ids of restored server connections; their secrets never travel, so the
  /// caller clears any same-id secret left by this device's old connections.
  final List<int> serverConnectionIds;
  final int rewrittenBooks;
  final int rewrittenCaches;

  const PreparedStagedRestore({
    required this.serverConnectionIds,
    required this.rewrittenBooks,
    required this.rewrittenCaches,
  });
}

/// Every `books/<dir>` path the app stores is absolute; this is the segment
/// that survives a change of data root (see `BookRepository.claimedDirNames`).
const _booksAnchor = '/${StagedFullRestore.booksDirName}/';

/// Validates and fixes up an extracted full backup in place, then writes the
/// READY marker. Runs at boot, after the native job wrote EXTRACTED and
/// before anything on the live device changes, so a failure here is
/// "restore failed, nothing happened".
///
/// - Refuses a database schema newer than this build. (No `quick_check`:
///   the staged file is a CRC-verified copy of a `VACUUM INTO` output, and
///   reading every page of a multi-gigabyte database on each launch until
///   READY exists is not worth the redundant assurance.)
/// - Rewrites `books.file_path`, `books.cover_image_path` and the
///   `imageDirPath` inside every manga cache from the first `/books/` onto
///   [PrepareStagedRestoreArgs.rootPath]. Anchoring on the segment rather
///   than on the source root keeps it idempotent and independent of the
///   manifest.
/// - Manga that were linked from a folder outside Mekuru and whose pages the
///   archive carries (`<dir>/pages/`) become ordinary manga: the cache drops
///   its folder link and reads from `pages/`, and a `content://` cover is
///   replaced by the first page, the rule the import uses. A linked manga
///   without pages in the archive stays linked, to be re-linked by hand,
///   except where the link cannot be followed (an Android backup restored
///   on iOS): there the cover becomes the placeholder and the cache stops
///   naming the folder, so the book is an empty shell that keeps its reading
///   data instead of calling into a platform service that is not there.
/// - Disables server connections (their secrets are not in the archive).
/// - Fsyncs the database, then writes READY with `flush: true`, last.
Future<PreparedStagedRestore> prepareStagedRestore(
  PrepareStagedRestoreArgs args,
) async {
  final staging = Directory(args.stagingPath);
  final root = args.rootPath.replaceFirst(RegExp(r'/+$'), '');

  final dbFile = File(p.join(staging.path, StagedFullRestore.databaseFileName));
  if (!dbFile.existsSync()) {
    throw const FullBackupFormatException('The archive has no database');
  }
  final settingsFile = File(
    p.join(staging.path, StagedFullRestore.settingsEntryName),
  );
  if (!settingsFile.existsSync()) {
    throw const FullBackupFormatException('The archive has no settings file');
  }
  // Decoding now means a corrupt settings file fails here, not at boot.
  BackupSerializer.decode(await settingsFile.readAsString());

  final booksDir = Directory(
    p.join(staging.path, StagedFullRestore.booksDirName),
  )..createSync(recursive: true);

  final (ids, rewrittenBooks) = _fixUpDatabase(
    dbFile.path,
    root,
    booksDir,
    keepFolderLinks: args.keepFolderLinks,
  );
  final rewrittenCaches = await _rewriteMangaCaches(
    booksDir,
    root,
    keepFolderLinks: args.keepFolderLinks,
  );

  final raf = await dbFile.open(mode: FileMode.append);
  await raf.flush();
  await raf.close();

  await File(
    p.join(staging.path, StagedFullRestore.readyMarkerName),
  ).writeAsString(args.manifestJson, flush: true);

  return PreparedStagedRestore(
    serverConnectionIds: ids,
    rewrittenBooks: rewrittenBooks,
    rewrittenCaches: rewrittenCaches,
  );
}

(List<int>, int) _fixUpDatabase(
  String path,
  String root,
  Directory stagingBooks, {
  required bool keepFolderLinks,
}) {
  final Database db;
  try {
    db = sqlite3.open(path);
  } on SqliteException catch (e) {
    throw FullBackupFormatException('The database could not be opened: $e');
  }
  try {
    final version = db.userVersion;
    if (version > AppDatabase.latestSchemaVersion) {
      throw FullBackupFormatException(
        'Database schema $version is newer than this app supports '
        '(${AppDatabase.latestSchemaVersion})',
      );
    }
    final rewrittenBooks = _reanchorBookPaths(db, root);

    // A linked manga whose pages the archive carries takes its first page as
    // the cover; one without pages keeps the content:// URI and stays linked.
    for (final row in db.select(
      "SELECT id, file_path FROM books WHERE cover_image_path LIKE 'content://%'",
    )) {
      final dirs = BookRepository.claimedDirNames(row['file_path'] as String);
      if (dirs.isEmpty) continue;
      final dir = dirs.first;
      final first = _firstPageIn(p.join(stagingBooks.path, dir));
      if (first == null) continue;
      db.execute('UPDATE books SET cover_image_path = ? WHERE id = ?', [
        '$root$_booksAnchor$dir/${FullBackupManifest.linkedPagesDirName}/$first',
        row['id'],
      ]);
    }
    if (!keepFolderLinks) {
      db.execute(
        "UPDATE books SET cover_image_path = NULL "
        "WHERE cover_image_path LIKE 'content://%'",
      );
    }

    final ids = <int>[];
    final hasConnections = db
        .select(
          "SELECT 1 FROM sqlite_master WHERE type = 'table' "
          "AND name = 'server_connections'",
        )
        .isNotEmpty;
    if (hasConnections) {
      db.execute('UPDATE server_connections SET enabled = 0');
      for (final row in db.select('SELECT id FROM server_connections')) {
        ids.add(row['id'] as int);
      }
    }
    return (ids, rewrittenBooks);
  } on SqliteException catch (e) {
    throw FullBackupFormatException('The database is unreadable: $e');
  } finally {
    db.close();
  }
}

/// Moves `books.file_path` and `books.cover_image_path` onto [root] from
/// their `/books/` anchor; returns how many `file_path`s it touched.
int _reanchorBookPaths(Database db, String root) {
  var rewrittenBooks = 0;
  for (final column in ['file_path', 'cover_image_path']) {
    db.execute(
      'UPDATE books SET $column = ? || substr($column, instr($column, ?)) '
      'WHERE $column IS NOT NULL AND instr($column, ?) > 0',
      [root, _booksAnchor, _booksAnchor],
    );
    if (column == 'file_path') rewrittenBooks = db.updatedRows;
  }
  return rewrittenBooks;
}

/// Boot pass for a data root that moved under an installed library: iOS gives
/// the app container a new UUID on reinstall (and sometimes on update), and
/// Android can restore the app into a different data directory. Applies the
/// restore's re-anchoring to the live database and manga caches under
/// [rootPath]; a no-op (one SELECT) when nothing moved.
///
/// Must run before the database is opened, after any staged restore was
/// applied. Caches go first and the database last, so the database keeps
/// reporting "moved" until a pass ran to completion. Returns whether it
/// rewrote anything.
// ponytail: rewrites every manga cache on each root move (every Xcode
// reinstall). Store paths relative to the books root if that gets slow.
Future<bool> reanchorLibraryIfMoved(String rootPath) async {
  final root = rootPath.replaceFirst(RegExp(r'/+$'), '');
  final dbFile = File(p.join(root, StagedFullRestore.databaseFileName));
  if (!dbFile.existsSync()) return false;

  final db = sqlite3.open(dbFile.path);
  try {
    final moved = db.select(
      'SELECT 1 FROM books WHERE instr(file_path, ?1) > 0 '
      'AND substr(file_path, 1, length(?2)) != ?2 LIMIT 1',
      [_booksAnchor, '$root$_booksAnchor'],
    ).isNotEmpty;
    if (!moved) return false;

    final booksDir = Directory(p.join(root, StagedFullRestore.booksDirName));
    if (booksDir.existsSync()) await _rewriteMangaCaches(booksDir, root);
    _reanchorBookPaths(db, root);
    return true;
  } finally {
    db.close();
  }
}

Future<int> _rewriteMangaCaches(
  Directory booksDir,
  String root, {
  bool keepFolderLinks = true,
}) async {
  var rewritten = 0;
  await for (final entity in booksDir.list(followLinks: false)) {
    if (entity is! Directory) continue;
    final dir = p.basename(entity.path);
    for (final name in [
      mangaPagesCacheFileName,
      BookRepository.originalMokuroOcrBackupFileName,
    ]) {
      final file = File(p.join(entity.path, name));
      if (!file.existsSync()) continue;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) continue;
      final String? next;
      if (decoded.containsKey('safTreeUri') &&
          (_firstPageIn(entity.path) != null || !keepFolderLinks)) {
        decoded.remove('safTreeUri');
        decoded.remove('safImageDirRelativePath');
        next =
            '$root$_booksAnchor$dir/${FullBackupManifest.linkedPagesDirName}';
      } else {
        next = _reanchored(decoded['imageDirPath'], root);
      }
      if (next == null) continue;
      decoded['imageDirPath'] = next;
      await writeStringAtomic(file, jsonEncode(decoded));
      rewritten++;
    }
  }
  return rewritten;
}

/// [dir] moved onto [root] from its `/books/` anchor, or null when there is
/// nothing to change.
String? _reanchored(Object? dir, String root) {
  if (dir is! String) return null;
  final at = dir.indexOf(_booksAnchor);
  if (at < 0) return null;
  final next = root + dir.substring(at);
  return next == dir ? null : next;
}

/// The cover-order first image inside `<mangaDir>/pages/`, or null when the
/// archive brought no pages for this manga.
String? _firstPageIn(String mangaDir) {
  final pages = Directory(
    p.join(mangaDir, FullBackupManifest.linkedPagesDirName),
  );
  if (!pages.existsSync()) return null;
  final candidates = CbzParser.coverCandidates(
    pages
        .listSync(followLinks: false)
        .whereType<File>()
        .map((f) => p.basename(f.path)),
  );
  return candidates.isEmpty ? null : candidates.first;
}
