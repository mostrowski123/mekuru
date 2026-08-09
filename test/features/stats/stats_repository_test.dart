import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/reader/data/reader_session_tracker.dart';
import 'package:mekuru/features/stats/data/repositories/stats_repository.dart';

import '../../shared/test_database.dart';

class _FakeStopwatch extends Stopwatch {
  int fakeElapsedMs = 0;

  @override
  int get elapsedMilliseconds => fakeElapsedMs;
}

void main() {
  late AppDatabase db;
  late StatsRepository repository;

  setUp(() {
    db = createTestDatabase();
    repository = StatsRepository(db);
  });
  tearDown(() async => db.close());

  final earlier = DateTime(2026, 8, 1, 21, 30);
  final later = DateTime(2026, 8, 2, 9);

  test(
    'watchAllSessions emits sessions ordered by startedAt ascending',
    () async {
      await repository.insertSession(
        ReadingSessionsCompanion.insert(
          bookFormat: 'epub',
          startedAt: later,
          durationMs: 60000,
        ),
      );
      await repository.insertSession(
        ReadingSessionsCompanion.insert(
          bookFormat: 'manga',
          startedAt: earlier,
          durationMs: 30000,
        ),
      );

      final sessions = await repository.watchAllSessions().first;

      expect(sessions.map((s) => s.startedAt), [earlier, later]);
      expect(sessions.map((s) => s.bookFormat), ['manga', 'epub']);
    },
  );

  test(
    'watchAllWordEvents emits events ordered by createdAt ascending',
    () async {
      // Inserted through the repository, so createdAt defaults to "now".
      await repository.insertWordEvent(
        kind: 'saved',
        expression: '猫',
        source: 'epub',
      );
      // Inserted directly with an older timestamp, so it must sort first.
      await db
          .into(db.wordEvents)
          .insert(
            WordEventsCompanion.insert(
              kind: 'anki',
              expression: '犬',
              createdAt: Value(DateTime(2020, 1, 1)),
            ),
          );

      final events = await repository.watchAllWordEvents().first;

      expect(events.map((e) => e.expression), ['犬', '猫']);
      expect(events.last.kind, 'saved');
      expect(events.last.source, 'epub');
    },
  );

  // Pins the key contract between ReaderSessionTracker.takeSummary and
  // recordSessionSummary's untyped map reads.
  test('recordSessionSummary persists a tracker summary verbatim', () async {
    final stopwatch = _FakeStopwatch()..fakeElapsedMs = 90000;
    final tracker = ReaderSessionTracker(
      bookFormat: 'manga',
      stopwatch: stopwatch,
    );
    tracker.recordPageTurn();
    tracker.recordPageTurn();
    tracker.recordLookup(hit: true);
    tracker.recordCharactersRead(500);
    tracker.recordWordSaved();

    final summary = tracker.takeSummary(endReason: 'closed')!;
    await repository.recordSessionSummary(summary: summary, bookId: 7);

    final session = (await repository.getAllSessions()).single;
    expect(session.bookFormat, 'manga');
    expect(session.bookId, 7);
    expect(session.durationMs, 90000);
    expect(session.pagesTurned, 2);
    expect(session.charactersRead, 500);
    expect(session.lookups, 1);
    expect(session.wordsSaved, 1);
  });

  test('insertWordEvent defaults source to other', () async {
    await repository.insertWordEvent(kind: 'saved', expression: '本');

    final events = await repository.getAllWordEvents();

    expect(events.single.kind, 'saved');
    expect(events.single.expression, '本');
    expect(events.single.source, 'other');
  });

  test(
    'getAllSessions and getAllWordEvents return rows in ascending order',
    () async {
      await repository.insertSession(
        ReadingSessionsCompanion.insert(
          bookFormat: 'epub',
          startedAt: later,
          durationMs: 60000,
        ),
      );
      await repository.insertSession(
        ReadingSessionsCompanion.insert(
          bookFormat: 'manga',
          startedAt: earlier,
          durationMs: 30000,
        ),
      );
      await db
          .into(db.wordEvents)
          .insert(
            WordEventsCompanion.insert(
              kind: 'saved',
              expression: '空',
              createdAt: Value(later),
            ),
          );
      await db
          .into(db.wordEvents)
          .insert(
            WordEventsCompanion.insert(
              kind: 'anki',
              expression: '海',
              createdAt: Value(earlier),
            ),
          );

      expect((await repository.getAllSessions()).map((s) => s.startedAt), [
        earlier,
        later,
      ]);
      expect((await repository.getAllWordEvents()).map((e) => e.expression), [
        '海',
        '空',
      ]);
    },
  );
}
