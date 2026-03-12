import 'dart:convert';

import '../models/backup_manifest.dart';

/// Exception thrown when a backup file has a version newer than supported.
class BackupVersionException implements Exception {
  final int fileVersion;
  final int maxSupported;
  BackupVersionException(this.fileVersion, this.maxSupported);

  @override
  String toString() =>
      'This backup was created with a newer version of Mekuru '
      '(backup v$fileVersion, supported v$maxSupported). '
      'Please update the app.';
}

/// Exception thrown when a backup file cannot be parsed.
class BackupFormatException implements Exception {
  final String detail;
  BackupFormatException(this.detail);

  @override
  String toString() => 'Not a valid Mekuru backup file: $detail';
}

/// Converts between [BackupManifest] and JSON strings.
class BackupSerializer {
  /// Encodes a [BackupManifest] to a JSON string.
  static String encode(BackupManifest manifest) {
    final map = <String, dynamic>{
      'version': manifest.version,
      'appName': 'mekuru',
      'createdAt': manifest.createdAt.toUtc().toIso8601String(),
      'settings': {
        'app': manifest.settings.app,
        'reader': manifest.settings.reader,
      },
      'dictionaryPreferences': manifest.dictionaryPreferences
          .map(
            (preference) => {
              'name': preference.name,
              'sortOrder': preference.sortOrder,
              'isEnabled': preference.isEnabled,
            },
          )
          .toList(growable: false),
      'savedWords': manifest.savedWords
          .map(
            (w) => {
              'expression': w.expression,
              'reading': w.reading,
              'glossaries': w.glossaries,
              'sentenceContext': w.sentenceContext,
              'dateAdded': w.dateAdded.toUtc().toIso8601String(),
            },
          )
          .toList(),
      'books': manifest.books.map(_encodeBookEntry).toList(),
    };
    return jsonEncode(map);
  }

  /// Decodes a JSON string into a [BackupManifest].
  ///
  /// Throws [BackupFormatException] if the JSON is malformed.
  /// Throws [BackupVersionException] if the version is unsupported.
  static BackupManifest decode(String jsonString) {
    final dynamic parsed;
    try {
      parsed = jsonDecode(jsonString);
    } catch (e) {
      throw BackupFormatException('invalid JSON');
    }

    if (parsed is! Map<String, dynamic>) {
      throw BackupFormatException('expected a JSON object');
    }

    final version = parsed['version'];
    if (version is! int) {
      throw BackupFormatException('missing or invalid "version" field');
    }
    if (version > BackupManifest.currentVersion) {
      throw BackupVersionException(version, BackupManifest.currentVersion);
    }

    final createdAtStr = parsed['createdAt'];
    if (createdAtStr is! String) {
      throw BackupFormatException('missing or invalid "createdAt" field');
    }
    final createdAt = DateTime.tryParse(createdAtStr);
    if (createdAt == null) {
      throw BackupFormatException('invalid "createdAt" timestamp');
    }

    final settingsMap = parsed['settings'];
    if (settingsMap is! Map<String, dynamic>) {
      throw BackupFormatException('missing or invalid "settings" field');
    }

    final settings = BackupSettings(
      app: Map<String, dynamic>.from(
        settingsMap['app'] as Map<String, dynamic>? ?? {},
      ),
      reader: Map<String, dynamic>.from(
        settingsMap['reader'] as Map<String, dynamic>? ?? {},
      ),
    );

    final dictionaryPreferences = _decodeDictionaryPreferences(
      parsed['dictionaryPreferences'],
    );

    final savedWordsList = parsed['savedWords'];
    if (savedWordsList is! List) {
      throw BackupFormatException('missing or invalid "savedWords" field');
    }
    final savedWords = savedWordsList.map(_decodeSavedWord).toList();

    final booksList = parsed['books'];
    if (booksList is! List) {
      throw BackupFormatException('missing or invalid "books" field');
    }
    final books = booksList.map(_decodeBookEntry).toList();

    return BackupManifest(
      version: version,
      createdAt: createdAt,
      settings: settings,
      dictionaryPreferences: dictionaryPreferences,
      savedWords: savedWords,
      books: books,
    );
  }

  /// Decodes a single book entry JSON map into a [BackupBookEntry].
  /// Useful for decoding pending book data stored as JSON.
  static BackupBookEntry decodeBookEntry(String jsonString) {
    final dynamic parsed;
    try {
      parsed = jsonDecode(jsonString);
    } catch (e) {
      throw BackupFormatException('invalid book entry JSON');
    }
    if (parsed is! Map<String, dynamic>) {
      throw BackupFormatException('expected a JSON object for book entry');
    }
    return _decodeBookEntry(parsed);
  }

  static Map<String, dynamic> _encodeBookEntry(BackupBookEntry entry) {
    return {
      'bookKey': entry.bookKey,
      'title': entry.title,
      'bookType': entry.bookType,
      'language': entry.language,
      'pageProgressionDirection': entry.pageProgressionDirection,
      'primaryWritingMode': entry.primaryWritingMode,
      'lastReadCfi': entry.lastReadCfi,
      'readProgress': entry.readProgress,
      'lastReadAt': entry.lastReadAt?.toUtc().toIso8601String(),
      'overrideVerticalText': entry.overrideVerticalText,
      'overrideReadingDirection': entry.overrideReadingDirection,
      'bookmarks': entry.bookmarks
          .map(
            (b) => {
              'cfi': b.cfi,
              'progress': b.progress,
              'chapterTitle': b.chapterTitle,
              'userNote': b.userNote,
              'dateAdded': b.dateAdded.toUtc().toIso8601String(),
            },
          )
          .toList(),
      'highlights': entry.highlights
          .map(
            (h) => {
              'cfiRange': h.cfiRange,
              'selectedText': h.selectedText,
              'color': h.color,
              'userNote': h.userNote,
              'dateAdded': h.dateAdded.toUtc().toIso8601String(),
            },
          )
          .toList(),
    };
  }

  /// Encodes a single [BackupBookEntry] to a JSON string.
  /// Used for storing pending book data.
  static String encodeBookEntry(BackupBookEntry entry) {
    return jsonEncode(_encodeBookEntry(entry));
  }

  static BackupSavedWordEntry _decodeSavedWord(dynamic item) {
    if (item is! Map<String, dynamic>) {
      throw BackupFormatException('invalid saved word entry');
    }
    return BackupSavedWordEntry(
      expression: item['expression'] as String? ?? '',
      reading: item['reading'] as String? ?? '',
      glossaries: item['glossaries'] as String? ?? '[]',
      sentenceContext: item['sentenceContext'] as String? ?? '',
      dateAdded:
          DateTime.tryParse(item['dateAdded'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  static List<BackupDictionaryPreference> _decodeDictionaryPreferences(
    dynamic rawPreferences,
  ) {
    if (rawPreferences == null) return const [];
    if (rawPreferences is! List) {
      throw BackupFormatException('invalid "dictionaryPreferences" field');
    }
    return rawPreferences.map(_decodeDictionaryPreference).toList();
  }

  static BackupDictionaryPreference _decodeDictionaryPreference(dynamic item) {
    if (item is! Map<String, dynamic>) {
      throw BackupFormatException('invalid dictionary preference entry');
    }
    return BackupDictionaryPreference(
      name: item['name'] as String? ?? '',
      sortOrder: item['sortOrder'] as int? ?? 0,
      isEnabled: item['isEnabled'] as bool? ?? true,
    );
  }

  static BackupBookEntry _decodeBookEntry(dynamic item) {
    if (item is! Map<String, dynamic>) {
      throw BackupFormatException('invalid book entry');
    }

    final bookmarksList = item['bookmarks'] as List? ?? [];
    final highlightsList = item['highlights'] as List? ?? [];

    return BackupBookEntry(
      bookKey: item['bookKey'] as String? ?? '',
      title: item['title'] as String? ?? '',
      bookType: item['bookType'] as String? ?? 'epub',
      language: item['language'] as String?,
      pageProgressionDirection: item['pageProgressionDirection'] as String?,
      primaryWritingMode: item['primaryWritingMode'] as String?,
      lastReadCfi: item['lastReadCfi'] as String?,
      readProgress: (item['readProgress'] as num?)?.toDouble() ?? 0.0,
      lastReadAt: item['lastReadAt'] != null
          ? DateTime.tryParse(item['lastReadAt'] as String)
          : null,
      overrideVerticalText: item['overrideVerticalText'] as bool?,
      overrideReadingDirection: item['overrideReadingDirection'] as String?,
      bookmarks: bookmarksList.map(_decodeBookmark).toList(),
      highlights: highlightsList.map(_decodeHighlight).toList(),
    );
  }

  static BackupBookmarkEntry _decodeBookmark(dynamic item) {
    if (item is! Map<String, dynamic>) {
      throw BackupFormatException('invalid bookmark entry');
    }
    return BackupBookmarkEntry(
      cfi: item['cfi'] as String? ?? '',
      progress: (item['progress'] as num?)?.toDouble() ?? 0.0,
      chapterTitle: item['chapterTitle'] as String? ?? '',
      userNote: item['userNote'] as String? ?? '',
      dateAdded:
          DateTime.tryParse(item['dateAdded'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  static BackupHighlightEntry _decodeHighlight(dynamic item) {
    if (item is! Map<String, dynamic>) {
      throw BackupFormatException('invalid highlight entry');
    }
    return BackupHighlightEntry(
      cfiRange: item['cfiRange'] as String? ?? '',
      selectedText: item['selectedText'] as String? ?? '',
      color: item['color'] as String? ?? 'yellow',
      userNote: item['userNote'] as String? ?? '',
      dateAdded:
          DateTime.tryParse(item['dateAdded'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
