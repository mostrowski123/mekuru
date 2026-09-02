import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/sync/data/models/remote_models.dart';
import 'package:mekuru/features/sync/data/repositories/server_connection_repository.dart';
import 'package:mekuru/features/sync/data/services/progress_sync_service.dart';
import 'package:mekuru/features/sync/data/services/server_client.dart';

import 'shared/fake_server_client.dart';
import 'shared/test_database.dart';

class FakeServerClient extends StubServerClient {
  RemoteProgress? pullResult;
  SyncException? failure;
  final List<(Map<String, String>, RemoteProgress)> pushes = [];
  int pullCalls = 0;

  @override
  Future<RemoteProgress?> pullProgress(Map<String, String> ids) async {
    if (failure != null) throw failure!;
    pullCalls++;
    return pullResult;
  }

  @override
  Future<void> pushProgress(
    Map<String, String> ids,
    RemoteProgress progress,
  ) async {
    if (failure != null) throw failure!;
    pushes.add((ids, progress));
  }
}

void main() {
  late AppDatabase db;
  late ServerConnectionRepository connections;
  late FakeServerClient client;
  late ProgressSyncService service;
  late int connectionId;

  final readAt = DateTime.utc(2026, 9, 1, 10);
  final before = DateTime.utc(2026, 9, 1, 9);
  final after = DateTime.utc(2026, 9, 1, 11);

  setUp(() async {
    db = createTestDatabase();
    connections = ServerConnectionRepository(db);
    client = FakeServerClient();
    service = ProgressSyncService(
      db: db,
      connections: connections,
      clientFactory: (_) async => client,
      pushDebounce: const Duration(milliseconds: 5),
    );
    connectionId = await connections.create(
      serverType: 'komga',
      name: 'Home',
      baseUrl: 'http://nas',
    );
  });

  tearDown(() async {
    BookRepository.onProgressWritten = null;
    service.dispose();
    await db.close();
  });

  Future<Book> insertLinkedManga({
    String? cfi = '5',
    double progress = 0.25,
    DateTime? lastReadAt,
    DateTime? lastSyncedAt,
    int totalPages = 21,
  }) async {
    final id = await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            title: '漫画',
            filePath: '/m',
            bookType: const Value('manga'),
            totalPages: Value(totalPages),
            lastReadCfi: Value(cfi),
            readProgress: Value(progress),
            lastReadAt: Value(lastReadAt),
            lastSyncedAt: Value(lastSyncedAt),
            serverConnectionId: Value(connectionId),
            remoteIds: const Value('{"bookId":"b1","seriesId":"s1"}'),
          ),
        );
    return (await (db.select(
      db.books,
    )..where((t) => t.id.equals(id))).getSingle());
  }

  Future<Book> reload(int id) =>
      (db.select(db.books)..where((t) => t.id.equals(id))).getSingle();

  test('progress writes push via the debounced repository hook', () async {
    final repo = BookRepository(db);
    BookRepository.onProgressWritten = service.schedulePush;
    final book = await insertLinkedManga(lastReadAt: readAt);

    await repo.updateProgress(book.id, '7', progress: 0.35);
    expect(client.pushes, isEmpty, reason: 'push is debounced');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(client.pushes, hasLength(1));
    final (ids, pushed) = client.pushes.single;
    expect(ids['bookId'], 'b1');
    expect(pushed.page, 7);
    expect(pushed.completed, isFalse);
    expect((await reload(book.id)).lastSyncedAt, isNotNull);
  });

  test('rapid writes collapse into one push', () async {
    final repo = BookRepository(db);
    BookRepository.onProgressWritten = service.schedulePush;
    final book = await insertLinkedManga(lastReadAt: readAt);

    for (var page = 6; page <= 10; page++) {
      await repo.updateProgress(book.id, '$page', progress: page / 20);
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(client.pushes, hasLength(1));
    expect(client.pushes.single.$2.page, 10);
  });

  test('syncOnOpen pushes first when local is newer than last sync', () async {
    final book = await insertLinkedManga(
      lastReadAt: readAt,
      lastSyncedAt: before,
    );
    client.pullResult = null;

    final remote = await service.syncOnOpen(book);

    expect(remote, isNull);
    expect(client.pushes, hasLength(1));
    expect(client.pushes.single.$2.page, 5);
  });

  test('syncOnOpen applies a strictly newer remote state', () async {
    final book = await insertLinkedManga(lastReadAt: readAt);
    client.pullResult = RemoteProgress(
      page: 12,
      completed: false,
      lastModified: after,
    );

    final remote = await service.syncOnOpen(book);

    expect(remote, isNotNull);
    expect(remote!.page, 12);
    final updated = await reload(book.id);
    expect(updated.lastReadCfi, '12');
    expect(updated.readProgress, closeTo(12 / 20, 0.001));
    // Applying remote state must not masquerade as local reading.
    expect(updated.lastReadAt, book.lastReadAt);
    expect(updated.lastSyncedAt, isNotNull);
  });

  test('syncOnOpen never lowers local progress when local is newer', () async {
    final book = await insertLinkedManga(
      cfi: '15',
      progress: 0.75,
      lastReadAt: readAt,
      lastSyncedAt: readAt,
    );
    client.pullResult = RemoteProgress(
      page: 3,
      completed: false,
      lastModified: before,
    );

    final remote = await service.syncOnOpen(book);

    expect(remote, isNull);
    final unchanged = await reload(book.id);
    expect(unchanged.lastReadCfi, '15');
    expect(unchanged.readProgress, 0.75);
  });

  test('a remote state without a timestamp loses to local reading', () async {
    final book = await insertLinkedManga(lastReadAt: readAt);
    client.pullResult = const RemoteProgress(page: 12);

    expect(await service.syncOnOpen(book), isNull);
    expect((await reload(book.id)).lastReadCfi, '5');
  });

  test('a remote state applies to a never-read local book', () async {
    final book = await insertLinkedManga(
      cfi: null,
      progress: 0.0,
      lastReadAt: null,
    );
    client.pullResult = const RemoteProgress(page: 8);

    final remote = await service.syncOnOpen(book);

    expect(remote, isNotNull);
    expect((await reload(book.id)).lastReadCfi, '8');
  });

  test('epub apply writes progress fields but never the CFI', () async {
    final id = await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            title: '小説',
            filePath: '/e',
            bookType: const Value('epub'),
            lastReadCfi: const Value('epubcfi(/6/4!/4/2/1:0)'),
            readProgress: const Value(0.2),
            lastReadAt: Value(readAt),
            serverConnectionId: Value(connectionId),
            remoteIds: const Value('{"bookId":"b2","epub":"true"}'),
          ),
        );
    final book = await reload(id);
    client.pullResult = RemoteProgress(
      href: 'OEBPS/ch5.xhtml',
      progression: 0.5,
      totalProgression: 0.6,
      lastModified: after,
    );

    final remote = await service.syncOnOpen(book);

    expect(remote, isNotNull);
    final updated = await reload(id);
    expect(updated.readProgress, closeTo(0.6, 0.001));
    expect(updated.lastReadHref, 'OEBPS/ch5.xhtml');
    expect(updated.lastReadProgression, closeTo(0.5, 0.001));
    expect(updated.lastReadCfi, 'epubcfi(/6/4!/4/2/1:0)');
    expect(updated.lastReadAt, book.lastReadAt);
  });

  test('an unreachable server fails silently and changes nothing', () async {
    final book = await insertLinkedManga(
      lastReadAt: readAt,
      lastSyncedAt: before,
    );
    client.failure = const SyncException(0, 'refused');

    expect(await service.syncOnOpen(book), isNull);
    final unchanged = await reload(book.id);
    expect(unchanged.lastReadCfi, '5');
    expect(unchanged.lastSyncedAt!.toUtc(), before);
  });

  test('unlinked books and disabled connections are ignored', () async {
    final unlinkedId = await db
        .into(db.books)
        .insert(BooksCompanion.insert(title: 'local', filePath: '/l'));
    final unlinked = await reload(unlinkedId);
    expect(await service.syncOnOpen(unlinked), isNull);

    final linked = await insertLinkedManga(lastReadAt: readAt);
    await connections.updateConnection(connectionId, enabled: false);
    // Let the cache-invalidation stream event land before the next call.
    await Future<void>.delayed(Duration.zero);
    expect(await service.syncOnOpen(linked), isNull);
    expect(client.pullCalls, 0);
    expect(client.pushes, isEmpty);
  });

  test('syncAll pushes only books with unsynced local reading', () async {
    await insertLinkedManga(lastReadAt: readAt, lastSyncedAt: before);
    await insertLinkedManga(lastReadAt: readAt, lastSyncedAt: after);
    await insertLinkedManga(lastReadAt: null);

    final result = await service.syncAll();

    expect(result.pushed, 1);
    expect(result.failed, 0);
    expect(client.pushes, hasLength(1));
  });

  test('syncOnOpen ignores the record this device itself pushed', () async {
    // Pushed (lastSyncedAt) after the last local read; the server echoes
    // that push back stamped in between the two.
    final book = await insertLinkedManga(
      lastReadAt: readAt,
      lastSyncedAt: after,
    );
    client.pullResult = RemoteProgress(
      page: 12,
      lastModified: readAt.add(const Duration(minutes: 30)),
    );

    expect(await service.syncOnOpen(book), isNull);
    expect((await reload(book.id)).lastReadCfi, '5');
  });

  test(
    'an epub remote with no whole-book fraction is not marked synced',
    () async {
      final id = await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(
              title: '小説',
              filePath: '/e',
              bookType: const Value('epub'),
              lastReadAt: Value(readAt),
              serverConnectionId: Value(connectionId),
              remoteIds: const Value('{"bookId":"b2","epub":"true"}'),
            ),
          );
      client.pullResult = RemoteProgress(page: 40, lastModified: after);

      expect(await service.syncOnOpen(await reload(id)), isNull);
      expect((await reload(id)).lastSyncedAt, isNull);
    },
  );
}
