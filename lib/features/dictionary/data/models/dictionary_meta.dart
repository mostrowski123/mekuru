import 'package:drift/drift.dart';

/// DictionaryMetas table — metadata for imported Yomitan dictionaries.
class DictionaryMetas extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  BoolColumn get isEnabled => boolean().withDefault(const Constant(true))();
  DateTimeColumn get dateImported =>
      dateTime().withDefault(currentDateAndTime)();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isHidden => boolean().withDefault(const Constant(false))();

  /// index.json `revision`, shown as the dictionary's version. Null for
  /// dictionaries imported before schema 24.
  TextColumn get revision => text().nullable()();
}

/// Id of the user dictionary ("My definitions"), which holds the user's own
/// entries and is created on first use. Imports can never get it: the
/// table's AUTOINCREMENT ids start at 1.
const userDictionaryId = 0;
