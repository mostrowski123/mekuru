import 'package:mekuru/core/database/database_provider.dart';

/// Describes one full-backup archive (`mekuru-full-backup-*.zip`).
///
/// Written as the FIRST zip entry so the importer can validate it before
/// touching the rest of a multi-gigabyte stream. Counts and sizes feed the
/// confirmation dialog and the free-space check; [appSupportPath] is
/// informational — restore rewrites absolute paths from the `/books/` anchor,
/// never from this value.
class FullBackupManifest {
  static const int currentFormat = 1;

  static const String manifestEntry = 'manifest.json';
  static const String settingsEntry = 'settings.mekuru';
  static const String databaseEntry = 'mekuru_db.sqlite';
  static const String booksPrefix = 'books/';

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
  final int entryCount;

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
    required this.entryCount,
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
    'entryCount': entryCount,
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
      entryCount: count('entryCount'),
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
