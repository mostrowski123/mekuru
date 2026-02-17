import 'package:drift/drift.dart';

/// Books table — stores imported EPUB metadata and reading progress.
class Books extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text()();
  TextColumn get filePath => text()();
  TextColumn get coverImagePath => text().nullable()();
  IntColumn get totalPages => integer().withDefault(const Constant(0))();
  TextColumn get lastReadCfi => text().nullable()();
  RealColumn get readProgress => real().withDefault(const Constant(0.0))();
  DateTimeColumn get dateAdded => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get lastReadAt => dateTime().nullable()();
  TextColumn get language => text().nullable()();
  TextColumn get pageProgressionDirection => text().nullable()();

  /// User's per-book override for vertical text display.
  /// `null` means "use the book's default" (based on language/ppd).
  BoolColumn get overrideVerticalText => boolean().nullable()();

  /// User's per-book override for reading direction ('ltr' or 'rtl').
  /// `null` means "use the book's default" (based on language/ppd).
  TextColumn get overrideReadingDirection => text().nullable()();
}
