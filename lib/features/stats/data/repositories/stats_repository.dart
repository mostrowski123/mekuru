import 'package:drift/drift.dart';

import '../../../../core/database/database_provider.dart';

/// CRUD for the stats tables. Writes are small and infrequent (a few rows
/// per day); readers watch the full table and aggregate in memory.
class StatsRepository {
  StatsRepository(this._db);

  final AppDatabase _db;

  Future<void> insertSession(ReadingSessionsCompanion entry) =>
      _db.into(_db.readingSessions).insert(entry);

  Future<void> insertWordEvent({
    required String kind,
    required String expression,
    String source = 'other',
  }) => _db
      .into(_db.wordEvents)
      .insert(
        WordEventsCompanion.insert(
          kind: kind,
          expression: expression,
          source: Value(source),
        ),
      );

  Stream<List<ReadingSession>> watchAllSessions() => (_db.select(
    _db.readingSessions,
  )..orderBy([(t) => OrderingTerm.asc(t.startedAt)])).watch();

  Stream<List<WordEvent>> watchAllWordEvents() => (_db.select(
    _db.wordEvents,
  )..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).watch();

  Future<List<ReadingSession>> getAllSessions() => (_db.select(
    _db.readingSessions,
  )..orderBy([(t) => OrderingTerm.asc(t.startedAt)])).get();

  Future<List<WordEvent>> getAllWordEvents() => (_db.select(
    _db.wordEvents,
  )..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).get();
}
