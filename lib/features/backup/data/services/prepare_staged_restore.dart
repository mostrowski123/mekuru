import 'dart:convert';
import 'dart:io';

import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/utils/atomic_file.dart';
import 'package:mekuru/features/backup/data/models/full_backup_manifest.dart';
import 'package:mekuru/features/backup/data/services/backup_serializer.dart';
import 'package:mekuru/features/backup/data/services/staged_full_restore.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// Arguments for [prepareStagedRestore]; plain strings so it can run under
/// `compute()`.
class PrepareStagedRestoreArgs {
  final String stagingPath;
  final String rootPath;
  final String manifestJson;

  const PrepareStagedRestoreArgs({
    required this.stagingPath,
    required this.rootPath,
    required this.manifestJson,
  });
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
///   manifest; `content://` covers and SAF image folders contain no anchor
///   and are left alone.
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

  final (ids, rewrittenBooks) = _fixUpDatabase(dbFile.path, root);
  final rewrittenCaches = await _rewriteMangaCaches(booksDir, root);

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

(List<int>, int) _fixUpDatabase(String path, String root) {
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
    var rewrittenBooks = 0;
    for (final column in ['file_path', 'cover_image_path']) {
      db.execute(
        'UPDATE books SET $column = ? || substr($column, instr($column, ?)) '
        'WHERE $column IS NOT NULL AND instr($column, ?) > 0',
        [root, _booksAnchor, _booksAnchor],
      );
      if (column == 'file_path') rewrittenBooks = db.updatedRows;
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

Future<int> _rewriteMangaCaches(Directory booksDir, String root) async {
  var rewritten = 0;
  await for (final entity in booksDir.list(followLinks: false)) {
    if (entity is! Directory) continue;
    for (final name in [
      mangaPagesCacheFileName,
      BookRepository.originalMokuroOcrBackupFileName,
    ]) {
      final file = File(p.join(entity.path, name));
      if (!file.existsSync()) continue;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) continue;
      final dir = decoded['imageDirPath'];
      if (dir is! String) continue;
      final at = dir.indexOf(_booksAnchor);
      if (at < 0) continue;
      final next = root + dir.substring(at);
      if (next == dir) continue;
      decoded['imageDirPath'] = next;
      await writeStringAtomic(file, jsonEncode(decoded));
      rewritten++;
    }
  }
  return rewritten;
}
