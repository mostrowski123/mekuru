import 'package:drift/drift.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

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

  /// Persists one reader session from the summary a `ReaderSessionTracker`
  /// handed back.
  ///
  /// Owns the whole write on both readers' behalf, including the arithmetic
  /// that turns an elapsed duration into a start instant: the tracker measures
  /// how long the slice lasted, and the row is keyed on when it began.
  /// `DateTime.now()` is read before the first await, so the start instant is
  /// the moment the session ended rather than whenever the insert is scheduled.
  ///
  /// Never throws. The callers are fire-and-forget — one of them runs from
  /// `dispose()` — so a failed write is reported and swallowed rather than
  /// surfacing as an unhandled async error.
  Future<void> recordSessionSummary({
    required Map<String, Object> summary,
    int? bookId,
  }) async {
    try {
      final durationMs = summary['duration_ms'] as int;
      await insertSession(
        ReadingSessionsCompanion.insert(
          bookId: Value(bookId),
          bookFormat: summary['book_format'] as String,
          startedAt: DateTime.now().subtract(
            Duration(milliseconds: durationMs),
          ),
          durationMs: durationMs,
          pagesTurned: Value(summary['pages_turned'] as int),
          charactersRead: Value(summary['characters_read'] as int),
          lookups: Value(summary['lookups'] as int),
          wordsSaved: Value(summary['words_saved'] as int),
        ),
      );
    } catch (e, st) {
      await Sentry.captureException(e, stackTrace: st);
    }
  }

  Stream<List<ReadingSession>> watchAllSessions() => _sessionsQuery().watch();

  Stream<List<WordEvent>> watchAllWordEvents() => _wordEventsQuery().watch();

  Future<List<ReadingSession>> getAllSessions() => _sessionsQuery().get();

  Future<List<WordEvent>> getAllWordEvents() => _wordEventsQuery().get();

  /// Every session, oldest first — the order the aggregator's windowing
  /// assumes.
  SimpleSelectStatement<$ReadingSessionsTable, ReadingSession>
  _sessionsQuery() =>
      _db.select(_db.readingSessions)
        ..orderBy([(t) => OrderingTerm.asc(t.startedAt)]);

  /// Every word event, oldest first — `cumulativeUniqueWords` credits an
  /// expression to its first event, so the order is load-bearing.
  SimpleSelectStatement<$WordEventsTable, WordEvent> _wordEventsQuery() =>
      _db.select(_db.wordEvents)
        ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
}
