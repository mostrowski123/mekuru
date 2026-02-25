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

  /// User's per-book override for vertical text display.
  /// `null` means "use the book's default" (based on language/ppd).
  BoolColumn get overrideVerticalText => boolean().nullable()();

  /// User's per-book override for reading direction ('ltr' or 'rtl').
  /// `null` means "use the book's default" (based on language/ppd).
  TextColumn get overrideReadingDirection => text().nullable()();
}
