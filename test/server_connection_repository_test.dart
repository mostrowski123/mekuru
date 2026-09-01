import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/sync/data/repositories/server_connection_repository.dart';

import 'shared/test_database.dart';

void main() {
  late AppDatabase db;
  late ServerConnectionRepository repo;

  setUp(() {
    db = createTestDatabase();
    repo = ServerConnectionRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> insertBook({
    String title = '本',
    String bookType = 'manga',
    int? connectionId,
    String? remoteIds,
  }) => db
      .into(db.books)
      .insert(
        BooksCompanion.insert(
          title: title,
          filePath: '/test/$title',
          bookType: Value(bookType),
          serverConnectionId: connectionId != null
              ? Value(connectionId)
              : const Value.absent(),
          remoteIds: remoteIds != null
              ? Value(remoteIds)
              : const Value.absent(),
          lastReadCfi: const Value('5'),
          readProgress: const Value(0.5),
        ),
      );

  test('create, update, and watch connections', () async {
    final id = await repo.create(
      serverType: 'komga',
      name: 'Home',
      baseUrl: 'http://nas:25600',
    );

    var connection = await repo.getById(id);
    expect(connection!.serverType, 'komga');
    expect(connection.enabled, isTrue);

    await repo.updateConnection(id, name: 'NAS', enabled: false);
    connection = await repo.getById(id);
    expect(connection!.name, 'NAS');
    expect(connection.baseUrl, 'http://nas:25600');
    expect(connection.enabled, isFalse);
  });

  test('linkBook and findLinkedBook round-trip', () async {
    final connectionId = await repo.create(
      serverType: 'komga',
      name: 'Home',
      baseUrl: 'http://nas',
    );
    final bookId = await insertBook();

    await repo.linkBook(bookId, connectionId, {
      'bookId': 'abc',
      'seriesId': 's1',
    });

    final linked = await repo.findLinkedBook(connectionId, {
      'bookId': 'abc',
      'seriesId': 's1',
    });
    expect(linked!.id, bookId);
    // Linking never touches reading data.
    expect(linked.lastReadCfi, '5');
    expect(linked.readProgress, 0.5);

    expect(await repo.findLinkedBook(connectionId, {'bookId': 'zzz'}), isNull);
  });

  test('delete unlinks books but keeps their data intact', () async {
    final connectionId = await repo.create(
      serverType: 'kavita',
      name: 'K',
      baseUrl: 'http://k',
    );
    final bookId = await insertBook(
      connectionId: connectionId,
      remoteIds: '{"chapterId":"9"}',
    );

    await repo.delete(connectionId);

    expect(await repo.getById(connectionId), isNull);
    final book = await (db.select(
      db.books,
    )..where((t) => t.id.equals(bookId))).getSingle();
    expect(book.serverConnectionId, null);
    expect(book.remoteIds, null);
    expect(book.lastReadCfi, '5');
    expect(book.readProgress, 0.5);
  });

  test('findUnlinkedTitleMatch normalizes and filters', () async {
    final connectionId = await repo.create(
      serverType: 'komga',
      name: 'Home',
      baseUrl: 'http://nas',
    );
    await insertBook(title: 'Yotsuba&! ', bookType: 'manga');
    await insertBook(title: 'yotsuba&!', bookType: 'epub');
    final linkedId = await insertBook(
      title: 'Linked Manga',
      connectionId: connectionId,
      remoteIds: '{"bookId":"x"}',
    );

    final match = await repo.findUnlinkedTitleMatch('  YOTSUBA&!', 'manga');
    expect(match!.bookType, 'manga');
    expect(match.title, 'Yotsuba&! ');

    // Already-linked books are never offered.
    expect(await repo.findUnlinkedTitleMatch('Linked Manga', 'manga'), isNull);
    expect(linkedId, isNotNull);
    expect(await repo.findUnlinkedTitleMatch('Unknown', 'manga'), isNull);
  });

  test('decodeRemoteIds tolerates malformed JSON', () {
    expect(ServerConnectionRepository.decodeRemoteIds(null), isNull);
    expect(ServerConnectionRepository.decodeRemoteIds(''), isNull);
    expect(ServerConnectionRepository.decodeRemoteIds('not json'), isNull);
    expect(ServerConnectionRepository.decodeRemoteIds('{"bookId":"a"}'), {
      'bookId': 'a',
    });
    // Non-string values are stringified, not crashed on.
    expect(ServerConnectionRepository.decodeRemoteIds('{"chapterId":7}'), {
      'chapterId': '7',
    });
  });
}
