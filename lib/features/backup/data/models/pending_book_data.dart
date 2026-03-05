import 'package:drift/drift.dart';

/// Stores backup book entries that had no matching book at restore time.
/// Applied automatically when a matching book is later imported.
class PendingBookDatas extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Book identity key: "{bookType}::{normalizedTitle}".
  TextColumn get bookKey => text()();

  /// Full book entry JSON blob (bookmarks, highlights, progress, overrides).
  TextColumn get dataJson => text()();

  DateTimeColumn get dateAdded => dateTime().withDefault(currentDateAndTime)();
}
