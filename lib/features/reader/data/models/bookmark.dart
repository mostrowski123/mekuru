import 'package:drift/drift.dart';

import '../../../library/data/models/book.dart';

/// Bookmarks table — user-saved reading positions within a book.
class Bookmarks extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get bookId => integer().references(Books, #id)();
  TextColumn get cfi => text()();
  RealColumn get progress => real().withDefault(const Constant(0.0))();
  TextColumn get chapterTitle => text().withDefault(const Constant(''))();
  TextColumn get userNote => text().withDefault(const Constant(''))();
  DateTimeColumn get dateAdded => dateTime().withDefault(currentDateAndTime)();
}
