import 'package:mekuru/core/database/database_provider.dart';

/// Describes one full-backup archive (`mekuru-full-backup-*.zip`).
///
/// Written as the FIRST zip entry so the importer can validate it before
/// touching the rest of a multi-gigabyte stream. Counts and sizes feed the
/// confirmation dialog and the free-space check; [appSupportPath] is
/// informational: restore rewrites absolute paths from the `/books/` anchor,
/// never from this value.
///
/// Archive layout (kept in step with `ZipLayout` on the Kotlin side):
/// ```
/// manifest.json
/// README.txt
/// Mekuru data/settings.mekuru
/// Mekuru data/mekuru_db.sqlite
/// Mekuru data/covers/<loose files from books/>
/// Books/<Title>/...            one folder per EPUB, contents as on disk
/// Manga/<Title>/...            one folder per manga
/// ```
/// [folders] maps each `Books/<Title>/` or `Manga/<Title>/` prefix back to
/// the import directory name under `books/`, so a restore recreates the
/// on-device layout while a person sees titles.
class FullBackupManifest {
  static const int currentFormat = 1;

  static const String manifestEntry = 'manifest.json';
  static const String readmeEntry = 'README.txt';
  static const String dataPrefix = 'Mekuru data/';
  static const String coversPrefix = '${dataPrefix}covers/';
  static const String settingsFileName = 'settings.mekuru';
  static const String settingsEntry = '$dataPrefix$settingsFileName';
  static const String databaseEntry =
      '$dataPrefix${AppDatabase.databaseFileName}';
  static const String booksPrefix = 'Books/';
  static const String mangaPrefix = 'Manga/';

  final int format;
  final String appVersion;
  final int schemaVersion;
  final DateTime createdAt;
  final String appSupportPath;
  final int bookCount;
  final int dictionaryCount;

  /// Manga whose page images live in a user folder (SAF) and are therefore
  /// not inside the archive; they need re-linking on another device.
  final int externalMangaCount;
  final int dbBytes;
  final int booksBytes;

  /// Zip folder prefix (with trailing slash) → import directory name.
  final Map<String, String> folders;

  const FullBackupManifest({
    required this.format,
    required this.appVersion,
    required this.schemaVersion,
    required this.createdAt,
    required this.appSupportPath,
    required this.bookCount,
    required this.dictionaryCount,
    required this.externalMangaCount,
    required this.dbBytes,
    required this.booksBytes,
    this.folders = const {},
  });

  /// Uncompressed bytes a restore needs on disk.
  int get totalBytes => dbBytes + booksBytes;

  Map<String, dynamic> toJson() => {
    'format': format,
    'appVersion': appVersion,
    'schemaVersion': schemaVersion,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'appSupportPath': appSupportPath,
    'bookCount': bookCount,
    'dictionaryCount': dictionaryCount,
    'externalMangaCount': externalMangaCount,
    'dbBytes': dbBytes,
    'booksBytes': booksBytes,
    'folders': folders,
  };

  /// Parses a manifest, tolerating unknown keys and missing counts, and
  /// refusing archives this build cannot restore.
  factory FullBackupManifest.fromJson(Map<String, dynamic> json) {
    final format = json['format'];
    final appVersion = json['appVersion'];
    final schemaVersion = json['schemaVersion'];
    final createdAt = json['createdAt'];
    final appSupportPath = json['appSupportPath'];
    if (format is! int ||
        appVersion is! String ||
        schemaVersion is! int ||
        createdAt is! String ||
        appSupportPath is! String) {
      throw const FullBackupFormatException(
        'manifest.json is missing required fields',
      );
    }
    if (format > currentFormat ||
        schemaVersion > AppDatabase.latestSchemaVersion) {
      throw FullBackupTooNewException(
        appVersion: appVersion,
        format: format,
        schemaVersion: schemaVersion,
      );
    }
    int count(String key) => (json[key] as num?)?.toInt() ?? 0;
    final rawFolders = json['folders'];
    return FullBackupManifest(
      format: format,
      appVersion: appVersion,
      schemaVersion: schemaVersion,
      createdAt: DateTime.parse(createdAt),
      appSupportPath: appSupportPath,
      bookCount: count('bookCount'),
      dictionaryCount: count('dictionaryCount'),
      externalMangaCount: count('externalMangaCount'),
      dbBytes: count('dbBytes'),
      booksBytes: count('booksBytes'),
      folders: rawFolders is Map
          ? {
              for (final entry in rawFolders.entries)
                if (entry.key is String && entry.value is String)
                  entry.key as String: entry.value as String,
            }
          : const {},
    );
  }
}

/// The file is not a full backup, or its manifest is unreadable.
class FullBackupFormatException implements Exception {
  final String message;
  const FullBackupFormatException(this.message);

  @override
  String toString() => message;
}

/// The archive was written by a newer Mekuru than this build can restore.
class FullBackupTooNewException implements Exception {
  final String appVersion;
  final int format;
  final int schemaVersion;

  const FullBackupTooNewException({
    required this.appVersion,
    required this.format,
    required this.schemaVersion,
  });

  @override
  String toString() =>
      'Full backup from Mekuru $appVersion (format $format, schema '
      '$schemaVersion) needs a newer app version';
}
