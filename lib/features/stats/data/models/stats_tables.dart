import 'package:drift/drift.dart';

/// One row per completed reading session slice (see ReaderSessionTracker).
class ReadingSessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get bookId =>
      integer().nullable()(); // no FK: survives book deletion
  TextColumn get bookFormat => text()(); // 'epub' or 'manga'
  DateTimeColumn get startedAt => dateTime()();
  IntColumn get durationMs => integer()();
  IntColumn get pagesTurned => integer().withDefault(const Constant(0))();
  IntColumn get charactersRead => integer().withDefault(const Constant(0))();
  IntColumn get lookups => integer().withDefault(const Constant(0))();
  IntColumn get wordsSaved => integer().withDefault(const Constant(0))();
}

/// One row per vocabulary acquisition event (in-app save or AnkiDroid card).
class WordEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get kind => text()(); // 'saved' or 'anki'
  TextColumn get expression => text()();
  TextColumn get source => text().withDefault(
    const Constant('other'),
  )(); // 'epub' | 'manga' | 'other'
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
