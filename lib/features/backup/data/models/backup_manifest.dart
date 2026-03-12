// Typed data classes for backup JSON serialization/deserialization.

class BackupManifest {
  static const int currentVersion = 1;

  final int version;
  final DateTime createdAt;
  final BackupSettings settings;
  final List<BackupDictionaryPreference> dictionaryPreferences;
  final List<BackupSavedWordEntry> savedWords;
  final List<BackupBookEntry> books;

  const BackupManifest({
    required this.version,
    required this.createdAt,
    required this.settings,
    this.dictionaryPreferences = const [],
    required this.savedWords,
    required this.books,
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
