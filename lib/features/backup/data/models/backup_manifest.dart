// Typed data classes for backup JSON serialization/deserialization.

class BackupManifest {
  static const int currentVersion = 1;

  final int version;
  final DateTime createdAt;
  final BackupSettings settings;
  final List<BackupDictionaryPreference> dictionaryPreferences;
  final List<BackupSavedWordEntry> savedWords;
  final List<BackupBookEntry> books;

  /// Reading statistics. Additive within version 1: backups written before
  /// the stats tables existed simply omit these keys.
  final List<BackupReadingSessionEntry> readingSessions;
  final List<BackupWordEventEntry> wordEvents;

  /// Every collection name, including empty collections. Additive within
  /// version 1: older backups simply omit the key. Membership itself is
  /// stored per book in [BackupBookEntry.collections] so it travels through
  /// the pending-book-data path when a book is imported after the restore.
  final List<String> collections;

  /// Komga/Kavita connections (sans credentials). Additive within version
  /// 1: older backups simply omit the key.
  final List<BackupServerConnection> serverConnections;

  const BackupManifest({
    required this.version,
    required this.createdAt,
    required this.settings,
    this.dictionaryPreferences = const [],
    required this.savedWords,
    required this.books,
    this.readingSessions = const [],
    this.wordEvents = const [],
    this.collections = const [],
    this.serverConnections = const [],
  });
}

/// A Komga/Kavita server connection in a backup. [id] is the connection's
/// row id at backup time — restore remaps it. Credentials are never
/// included: restored connections come back disabled until the user
/// re-enters them.
class BackupServerConnection {
  final int id;
  final String serverType;
  final String name;
  final String baseUrl;

  const BackupServerConnection({
    required this.id,
    required this.serverType,
    required this.name,
    required this.baseUrl,
  });
}

/// A book's link to a server book. [connectionId] refers to the
/// [BackupServerConnection.id] in the same backup.
class BackupServerLink {
  final int connectionId;

  /// Raw `Books.remoteIds` JSON string.
  final String remoteIds;

  const BackupServerLink({required this.connectionId, required this.remoteIds});
}

class BackupDictionaryPreference {
  final String name;
  final int sortOrder;
  final bool isEnabled;

  const BackupDictionaryPreference({
    required this.name,
    required this.sortOrder,
    required this.isEnabled,
  });
}

class BackupSettings {
  final Map<String, dynamic> app;
  final Map<String, dynamic> reader;

  const BackupSettings({required this.app, required this.reader});
}

class BackupSavedWordEntry {
  final String expression;
  final String reading;
  final String glossaries;
  final String sentenceContext;
  final DateTime dateAdded;

  const BackupSavedWordEntry({
    required this.expression,
    required this.reading,
    required this.glossaries,
    required this.sentenceContext,
    required this.dateAdded,
  });
}

/// One row of the `ReadingSessions` table.
class BackupReadingSessionEntry {
  /// Informational only: never remapped or joined against Books on restore.
  final int? bookId;
  final String bookFormat;
  final DateTime startedAt;
  final int durationMs;
  final int pagesTurned;
  final int charactersRead;
  final int lookups;
  final int wordsSaved;

  const BackupReadingSessionEntry({
    this.bookId,
    required this.bookFormat,
    required this.startedAt,
    required this.durationMs,
    required this.pagesTurned,
    required this.charactersRead,
    required this.lookups,
    required this.wordsSaved,
  });
}

/// One row of the `WordEvents` table.
class BackupWordEventEntry {
  final String kind;
  final String expression;
  final String source;
  final DateTime createdAt;

  const BackupWordEventEntry({
    required this.kind,
    required this.expression,
    required this.source,
    required this.createdAt,
  });
}

class BackupBookEntry {
  final String bookKey;
  final String title;
  final String bookType;
  final String? language;
  final String? pageProgressionDirection;
  final String? primaryWritingMode;
  final String? lastReadCfi;
  final double readProgress;
  final DateTime? lastReadAt;
  final bool? overrideVerticalText;
  final String? overrideReadingDirection;

  /// Per-book furigana mode override (FuriganaMode storage value), null =
  /// follow the global setting.
  final String? furiganaMode;
  final List<BackupBookmarkEntry> bookmarks;
  final List<BackupHighlightEntry> highlights;

  /// Memberships of this book. Matched/created by collection name on
  /// restore; [BackupCollectionRef.position] preserves the manual order.
  final List<BackupCollectionRef> collections;

  /// Server link, when this book was linked to a Komga/Kavita book.
  final BackupServerLink? serverLink;

  const BackupBookEntry({
    required this.bookKey,
    required this.title,
    required this.bookType,
    this.language,
    this.pageProgressionDirection,
    this.primaryWritingMode,
    this.lastReadCfi,
    required this.readProgress,
    this.lastReadAt,
    this.overrideVerticalText,
    this.overrideReadingDirection,
    this.furiganaMode,
    required this.bookmarks,
    required this.highlights,
    this.collections = const [],
    this.serverLink,
  });

  /// Copy with [serverLink] replaced — restore uses this to remap backup
  /// connection ids onto this device's connection rows.
  BackupBookEntry copyWithServerLink(BackupServerLink? serverLink) =>
      BackupBookEntry(
        bookKey: bookKey,
        title: title,
        bookType: bookType,
        language: language,
        pageProgressionDirection: pageProgressionDirection,
        primaryWritingMode: primaryWritingMode,
        lastReadCfi: lastReadCfi,
        readProgress: readProgress,
        lastReadAt: lastReadAt,
        overrideVerticalText: overrideVerticalText,
        overrideReadingDirection: overrideReadingDirection,
        furiganaMode: furiganaMode,
        bookmarks: bookmarks,
        highlights: highlights,
        collections: collections,
        serverLink: serverLink,
      );
}

/// One collection membership in a backup. Encoded as {"name":…,
/// "position":…}; a bare string decodes to position 0 (the shape every
/// backup written before schema v22 uses).
class BackupCollectionRef {
  final String name;
  final int position;

  const BackupCollectionRef({required this.name, this.position = 0});
}

class BackupBookmarkEntry {
  final String cfi;
  final double progress;
  final String chapterTitle;
  final String userNote;
  final DateTime dateAdded;

  const BackupBookmarkEntry({
    required this.cfi,
    required this.progress,
    required this.chapterTitle,
    required this.userNote,
    required this.dateAdded,
  });
}

class BackupHighlightEntry {
  final String cfiRange;
  final String selectedText;
  final String color;
  final String userNote;
  final DateTime dateAdded;

  const BackupHighlightEntry({
    required this.cfiRange,
    required this.selectedText,
    required this.color,
    required this.userNote,
    required this.dateAdded,
  });
}
