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
}
