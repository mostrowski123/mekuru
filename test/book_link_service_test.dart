import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/sync/data/models/remote_models.dart';
import 'package:mekuru/features/sync/data/repositories/server_connection_repository.dart';
import 'package:mekuru/features/sync/data/services/book_link_service.dart';

import 'shared/fake_server_client.dart';
import 'shared/test_database.dart';

/// Serves a fixed catalog of one library / one series with [books].
class CatalogFakeClient extends StubServerClient {
  final List<RemoteBook> books;

  CatalogFakeClient(this.books);

  @override
  Future<List<RemoteLibrary>> listLibraries() async => const [
    RemoteLibrary(id: 'lib1', name: 'Manga'),
  ];

  @override
  Future<List<RemoteSeries>> listSeries(String libraryId, {String? search}) =>
      Future.value(const [
        RemoteSeries(id: 's1', libraryId: 'lib1', title: 'よつばと！', bookCount: 2),
      ]);

  @override
  Future<List<RemoteBook>> listBooks(RemoteSeries series) async => books;
}

void main() {
  late AppDatabase db;
  late ServerConnectionRepository connections;
  late BookLinkService service;
  late ServerConnection connection;

  setUp(() async {
    db = createTestDatabase();
    connections = ServerConnectionRepository(db);
    service = BookLinkService(db, connections);
    final id = await connections.create(
      serverType: 'komga',
      name: 'Home',
      baseUrl: 'http://nas',
    );
    connection = (await connections.getById(id))!;
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> insertBook(String title, {String bookType = 'manga'}) => db
      .into(db.books)
      .insert(
        BooksCompanion.insert(
          title: title,
          filePath: '/b/$title',
          bookType: Value(bookType),
          lastReadCfi: const Value('5'),
          readProgress: const Value(0.4),
        ),
      );

  RemoteBook remote(
    String id,
    String title, {
    RemoteBookFormat format = RemoteBookFormat.imageArchive,
  }) => RemoteBook(
    ids: {'bookId': id, 'seriesId': 's1'},
    title: title,
    seriesTitle: 'よつばと！',
    format: format,
    pageCount: 100,
  );

  test('links unique title matches without touching reading data', () async {
    final bookId = await insertBook('よつばと！ 1 ');
    final client = CatalogFakeClient([remote('b1', 'よつばと！ 1')]);

    final result = await service.linkExistingBooks(connection, client);

    expect(result.linkedBookIds, [bookId]);
    expect(result.unmatched, 0);
    final book = await (db.select(
      db.books,
    )..where((t) => t.id.equals(bookId))).getSingle();
    expect(book.serverConnectionId, connection.id);
    expect(
      ServerConnectionRepository.decodeRemoteIds(book.remoteIds)?['bookId'],
      'b1',
    );
    expect(book.lastReadCfi, '5');
    expect(book.readProgress, 0.4);
  });

  test('matches through the series+title key', () async {
    final bookId = await insertBook('よつばと！ 第1巻');
    final client = CatalogFakeClient([remote('b1', '第1巻')]);

    final result = await service.linkExistingBooks(connection, client);

    expect(result.linkedBookIds, [bookId]);
  });

  test('never links across formats', () async {
    await insertBook('novel', bookType: 'epub');
    final client = CatalogFakeClient([
      remote('b1', 'novel', format: RemoteBookFormat.imageArchive),
    ]);

    final result = await service.linkExistingBooks(connection, client);

    expect(result.linkedBookIds, isEmpty);
    expect(result.unmatched, 1);
  });

  test('ambiguous remote titles are never auto-linked', () async {
    await insertBook('duplicate');
    final client = CatalogFakeClient([
      remote('b1', 'duplicate'),
      remote('b2', 'Duplicate'),
    ]);

    final result = await service.linkExistingBooks(connection, client);

    expect(result.linkedBookIds, isEmpty);
    expect(result.unmatched, 1);
  });

  test('a remote book already claimed locally is not linked twice', () async {
    final claimedId = await insertBook('claimed');
    await connections.linkBook(claimedId, connection.id, {
      'bookId': 'b1',
      'seriesId': 's1',
    });
    await insertBook('よつばと！ 1');
    // The same remote book also title-matches the second local copy.
    final client = CatalogFakeClient([remote('b1', 'よつばと！ 1')]);

    final result = await service.linkExistingBooks(connection, client);

    expect(result.linkedBookIds, isEmpty);
    expect(result.unmatched, 1);
  });
}
