import 'package:drift/drift.dart';

/// Books table — stores imported book metadata and reading progress.
/// Supports both EPUB and mokuro manga formats via [bookType].
class Books extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text()();
  TextColumn get filePath => text()();

  /// Book format: 'epub' or 'manga'. Defaults to 'epub' for backward compat.
  TextColumn get bookType => text().withDefault(const Constant('epub'))();
  TextColumn get coverImagePath => text().nullable()();
  IntColumn get totalPages => integer().withDefault(const Constant(0))();
  TextColumn get lastReadCfi => text().nullable()();
  RealColumn get readProgress => real().withDefault(const Constant(0.0))();
  DateTimeColumn get dateAdded => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get lastReadAt => dateTime().nullable()();
  TextColumn get language => text().nullable()();
  TextColumn get pageProgressionDirection => text().nullable()();

  /// The `primary-writing-mode` from OPF metadata (e.g. `vertical-rl`,
  /// `horizontal-tb`). Used to determine whether content is vertical text.
  TextColumn get primaryWritingMode => text().nullable()();

  /// Whether the EPUB's stylesheets/content declare a vertical
  /// `writing-mode` (sniffed at import). Fallback vertical-text signal when
  /// [primaryWritingMode] is absent. `null` means the book was imported
  /// before sniffing existed — the legacy language/ppd heuristic applies.
  BoolColumn get hasVerticalCss => boolean().nullable()();

  /// User's per-book override for vertical text display.
  /// `null` means "use the book's default" (based on language/ppd).
  BoolColumn get overrideVerticalText => boolean().nullable()();

  /// User's per-book override for reading direction ('ltr' or 'rtl').
  /// `null` means "use the book's default" (based on language/ppd).
  TextColumn get overrideReadingDirection => text().nullable()();

  /// User's per-book override for furigana mode (stored as the enum's
  /// [FuriganaModeStorage.storageValue]). `null` means "use the global
  /// default from ReaderSettings".
  TextColumn get furiganaMode => text().nullable()();

  /// ServerConnections row this book is linked to for sync; null for purely
  /// local books. FK enforcement is off app-wide — cleanup is manual in the
  /// repositories.
  IntColumn get serverConnectionId => integer().nullable()();

  /// Per-server remote id bundle as raw JSON (Komga: {bookId, seriesId};
  /// Kavita: {chapterId, volumeId, seriesId, libraryId}). Parse on read.
  TextColumn get remoteIds => text().nullable()();

  /// Last time progress was successfully synced with the linked server.
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();

  /// EPUB locator extras beside [lastReadCfi]: current spine item href and
  /// progression within it (0..1), for server progress APIs that speak
  /// href+progression rather than CFI.
  TextColumn get lastReadHref => text().nullable()();
  RealColumn get lastReadProgression => real().nullable()();
}
