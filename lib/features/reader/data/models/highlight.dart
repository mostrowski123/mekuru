import 'package:drift/drift.dart';

import '../../../library/data/models/book.dart';

/// Highlights table — user-created text highlights with optional notes.
class Highlights extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get bookId => integer().references(Books, #id)();
  TextColumn get cfiRange => text()();
  TextColumn get selectedText => text()();
  TextColumn get color => text().withDefault(const Constant('yellow'))();
  TextColumn get userNote => text().withDefault(const Constant(''))();
  DateTimeColumn get dateAdded => dateTime().withDefault(currentDateAndTime)();
}
