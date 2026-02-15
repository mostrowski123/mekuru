import 'package:drift/drift.dart';

/// DictionaryMetas table — metadata for imported Yomitan dictionaries.
class DictionaryMetas extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  BoolColumn get isEnabled => boolean().withDefault(const Constant(true))();
  DateTimeColumn get dateImported =>
      dateTime().withDefault(currentDateAndTime)();
}
