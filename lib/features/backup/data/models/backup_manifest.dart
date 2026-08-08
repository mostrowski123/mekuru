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
  });
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
  final List<BackupBookmarkEntry> bookmarks;
  final List<BackupHighlightEntry> highlights;

  /// Names of the collections this book belongs to. Matched/created by
  /// name on restore.
  final List<String> collections;

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
    required this.bookmarks,
    required this.highlights,
    this.collections = const [],
  });
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
