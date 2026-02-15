import 'package:drift/drift.dart';

/// SavedWords table — vocabulary entries saved by the user during reading.
class SavedWords extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get expression => text()();
  TextColumn get reading => text().withDefault(const Constant(''))();
  TextColumn get glossaries => text()(); // JSON-encoded List<String>
  TextColumn get sentenceContext => text().withDefault(const Constant(''))();
  DateTimeColumn get dateAdded => dateTime().withDefault(currentDateAndTime)();
}
