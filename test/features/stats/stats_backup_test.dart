import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/backup/data/models/backup_manifest.dart';
import 'package:mekuru/features/backup/data/repositories/pending_book_data_repository.dart';
import 'package:mekuru/features/backup/data/services/backup_serializer.dart';
import 'package:mekuru/features/backup/data/services/backup_service.dart';
import 'package:mekuru/features/backup/data/services/book_match_service.dart';
import 'package:mekuru/features/backup/data/services/restore_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/test_database.dart';

void main() {
  final sessionStartedAt = DateTime.utc(2026, 3, 5, 14, 30);
  final wordEventCreatedAt = DateTime.utc(2026, 3, 6, 9, 15);

  BackupManifest buildManifest({
    List<BackupReadingSessionEntry> readingSessions = const [],
    List<BackupWordEventEntry> wordEvents = const [],
  }) {
    return BackupManifest(
      version: BackupManifest.currentVersion,
      createdAt: DateTime.utc(2026, 3, 7, 8),
      settings: const BackupSettings(app: {}, reader: {}),
      savedWords: const [],
      books: const [],
      readingSessions: readingSessions,
      wordEvents: wordEvents,
    );
  }

  final sampleSession = BackupReadingSessionEntry(
    bookId: 42,
    bookFormat: 'epub',
    startedAt: sessionStartedAt,
    durationMs: 1800000,
    pagesTurned: 37,
    charactersRead: 5200,
    lookups: 12,
    wordsSaved: 4,
  );

  final sampleWordEvent = BackupWordEventEntry(
    kind: 'saved',
    expression: '食べる',
    source: 'epub',
    createdAt: wordEventCreatedAt,
  );

  group('BackupSerializer stats', () {
    test('round-trips a reading session and a word event', () {
      final manifest = buildManifest(
        readingSessions: [sampleSession],
        wordEvents: [sampleWordEvent],
      );

      final decoded = BackupSerializer.decode(
        BackupSerializer.encode(manifest),
      );

      final session = decoded.readingSessions.single;
      expect(session.bookId, 42);
      expect(session.bookFormat, 'epub');
      expect(session.startedAt, sessionStartedAt);
      expect(session.durationMs, 1800000);
      expect(session.pagesTurned, 37);
      expect(session.charactersRead, 5200);
      expect(session.lookups, 12);
      expect(session.wordsSaved, 4);

      final event = decoded.wordEvents.single;
      expect(event.kind, 'saved');
      expect(event.expression, '食べる');
      expect(event.source, 'epub');
      expect(event.createdAt, wordEventCreatedAt);
    });

    test('round-trips a session with a null bookId', () {
      final manifest = buildManifest(
        readingSessions: [
          BackupReadingSessionEntry(
            bookFormat: 'manga',
            startedAt: sessionStartedAt,
            durationMs: 60000,
            pagesTurned: 0,
            charactersRead: 0,
            lookups: 0,
            wordsSaved: 0,
          ),
        ],
      );

      final decoded = BackupSerializer.decode(
        BackupSerializer.encode(manifest),
      );

      expect(decoded.readingSessions.single.bookId, isNull);
      expect(decoded.readingSessions.single.bookFormat, 'manga');
    });

    test('keeps the manifest version at 1', () {
      final json =
          jsonDecode(BackupSerializer.encode(buildManifest()))
              as Map<String, dynamic>;

      expect(json['version'], 1);
      expect(BackupManifest.currentVersion, 1);
    });

    test('decodes a pre-stats backup without the new keys', () {
      // A v1 backup written before the stats tables existed: no
      // "readingSessions" / "wordEvents" keys at all.
      const legacyJson =
          '{"version":1,"appName":"mekuru",'
          '"createdAt":"2026-01-01T00:00:00.000Z",'
          '"settings":{"app":{},"reader":{}},'
          '"savedWords":[],"books":[]}';

      final decoded = BackupSerializer.decode(legacyJson);

      expect(decoded.readingSessions, isEmpty);
      expect(decoded.wordEvents, isEmpty);
    });
  });

  group('BackupService stats collection', () {
    late AppDatabase db;
    late BackupService backupService;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      db = createTestDatabase();
      backupService = BackupService(db, BookMatchService());
    });

    tearDown(() async => db.close());

    test('includes reading sessions and word events', () async {
      await db
          .into(db.readingSessions)
          .insert(
            ReadingSessionsCompanion.insert(
              bookId: const Value(7),
              bookFormat: 'manga',
              startedAt: sessionStartedAt,
              durationMs: 90000,
              pagesTurned: const Value(11),
              charactersRead: const Value(300),
              lookups: const Value(3),
              wordsSaved: const Value(1),
            ),
          );
      await db
          .into(db.wordEvents)
          .insert(
            WordEventsCompanion.insert(
              kind: 'anki',
              expression: '犬',
              source: const Value('manga'),
              createdAt: Value(wordEventCreatedAt),
            ),
          );

      final manifest = await backupService.createBackup();

      final session = manifest.readingSessions.single;
      expect(session.bookId, 7);
      expect(session.bookFormat, 'manga');
      expect(session.startedAt.toUtc(), sessionStartedAt);
      expect(session.durationMs, 90000);
      expect(session.pagesTurned, 11);
      expect(session.charactersRead, 300);
      expect(session.lookups, 3);
      expect(session.wordsSaved, 1);

      final event = manifest.wordEvents.single;
      expect(event.kind, 'anki');
      expect(event.expression, '犬');
      expect(event.source, 'manga');
      expect(event.createdAt.toUtc(), wordEventCreatedAt);
    });

    test('produces empty stats lists for an empty database', () async {
      final manifest = await backupService.createBackup();

      expect(manifest.readingSessions, isEmpty);
      expect(manifest.wordEvents, isEmpty);
    });
  });

  group('RestoreService.restoreStats', () {
    late AppDatabase db;
    late RestoreService restoreService;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      db = createTestDatabase();
      restoreService = RestoreService(
        db,
        BookMatchService(),
        PendingBookDataRepository(db),
      );
    });

    tearDown(() async => db.close());

    test('inserts rows with their original timestamps when tables are '
        'empty', () async {
      await restoreService.restoreStats(
        buildManifest(
          readingSessions: [sampleSession],
          wordEvents: [sampleWordEvent],
        ),
      );

      final session = (await db.select(db.readingSessions).get()).single;
      expect(session.bookId, 42);
      expect(session.bookFormat, 'epub');
      expect(session.startedAt.toUtc(), sessionStartedAt);
      expect(session.durationMs, 1800000);
      expect(session.pagesTurned, 37);
      expect(session.charactersRead, 5200);
      expect(session.lookups, 12);
      expect(session.wordsSaved, 4);

      final event = (await db.select(db.wordEvents).get()).single;
      expect(event.kind, 'saved');
      expect(event.expression, '食べる');
      expect(event.source, 'epub');
      expect(event.createdAt.toUtc(), wordEventCreatedAt);
    });

    test(
      'skips reading sessions when the local table already has rows',
      () async {
        await db
            .into(db.readingSessions)
            .insert(
              ReadingSessionsCompanion.insert(
                bookFormat: 'epub',
                startedAt: DateTime.utc(2025, 1, 1),
                durationMs: 1000,
              ),
            );

        await restoreService.restoreStats(
          buildManifest(
            readingSessions: [sampleSession],
            wordEvents: [sampleWordEvent],
          ),
        );

        final sessions = await db.select(db.readingSessions).get();
        expect(sessions, hasLength(1), reason: 'existing history is preserved');
        expect(sessions.single.durationMs, 1000);

        // Word events are checked independently, so they still restore.
        expect(await db.select(db.wordEvents).get(), hasLength(1));
      },
    );

    test('merges word events into existing local history', () async {
      await db
          .into(db.wordEvents)
          .insert(
            WordEventsCompanion.insert(
              kind: 'saved',
              expression: '本',
              createdAt: Value(DateTime.utc(2025, 1, 1)),
            ),
          );

      await restoreService.restoreStats(
        buildManifest(
          readingSessions: [sampleSession],
          wordEvents: [sampleWordEvent],
        ),
      );

      final events = await db.select(db.wordEvents).get();
      expect(events, hasLength(2), reason: 'local and backup history merge');
      expect(events.map((e) => e.expression), containsAll(['本', '食べる']));

      // Reading sessions are checked independently, so they still restore.
      expect(await db.select(db.readingSessions).get(), hasLength(1));
    });

    test('restores real word events over the v19 migration backfill', () async {
      // An upgrading user: the v19 migration synthesized word events from
      // saved_words (kind 'saved', source 'other'), so the table is not
      // empty when the restore runs.
      await db
          .into(db.wordEvents)
          .insert(
            WordEventsCompanion.insert(
              kind: 'saved',
              expression: '食べる',
              createdAt: Value(DateTime.utc(2025, 6, 1)),
            ),
          );

      await restoreService.restoreStats(
        buildManifest(
          wordEvents: [
            sampleWordEvent,
            BackupWordEventEntry(
              kind: 'anki',
              expression: '食べる',
              source: 'epub',
              createdAt: DateTime.utc(2026, 3, 6, 10),
            ),
          ],
        ),
      );

      final events = await db.select(db.wordEvents).get();
      expect(events, hasLength(3));
      // The backup's real reader-sourced history is queryable: the format
      // filter on the stats screen matches on source.
      final epubSourced = events.where((e) => e.source == 'epub');
      expect(epubSourced, hasLength(2));
      expect(events.where((e) => e.kind == 'anki'), hasLength(1));
    });

    test('merging skips events already present locally', () async {
      // The same event on both sides (e.g. a backup taken from this device):
      // identity is kind + expression + source + createdAt.
      await db
          .into(db.wordEvents)
          .insert(
            WordEventsCompanion.insert(
              kind: sampleWordEvent.kind,
              expression: sampleWordEvent.expression,
              source: Value(sampleWordEvent.source),
              createdAt: Value(sampleWordEvent.createdAt),
            ),
          );

      await restoreService.restoreStats(
        buildManifest(wordEvents: [sampleWordEvent]),
      );

      expect(await db.select(db.wordEvents).get(), hasLength(1));
    });

    test('a repeated restore does not duplicate rows', () async {
      final manifest = buildManifest(
        readingSessions: [sampleSession],
        wordEvents: [sampleWordEvent],
      );

      await restoreService.restoreStats(manifest);
      await restoreService.restoreStats(manifest);

      expect(await db.select(db.readingSessions).get(), hasLength(1));
      expect(await db.select(db.wordEvents).get(), hasLength(1));
    });
  });
}
