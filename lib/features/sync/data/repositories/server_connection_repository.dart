import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:mekuru/core/database/database_provider.dart';

/// CRUD for server connections plus the book-link columns.
///
/// FK enforcement is off app-wide, so [delete] performs the manual
/// "cascade": it unlinks the connection's books (link columns only —
/// book files, progress, and stats are never touched).
class ServerConnectionRepository {
  final AppDatabase _db;

  ServerConnectionRepository(this._db);

  Stream<List<ServerConnection>> watchConnections() => (_db.select(
    _db.serverConnections,
  )..orderBy([(t) => OrderingTerm.asc(t.id)])).watch();

  Future<ServerConnection?> getById(int id) => (_db.select(
    _db.serverConnections,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<int> create({
    required String serverType,
    required String name,
    required String baseUrl,
  }) => _db
      .into(_db.serverConnections)
      .insert(
        ServerConnectionsCompanion.insert(
          serverType: serverType,
          name: name,
          baseUrl: baseUrl,
        ),
      );

  Future<void> updateConnection(
    int id, {
    String? name,
    String? baseUrl,
    bool? enabled,
  }) =>
      (_db.update(_db.serverConnections)..where((t) => t.id.equals(id))).write(
        ServerConnectionsCompanion(
          name: name != null ? Value(name) : const Value.absent(),
          baseUrl: baseUrl != null ? Value(baseUrl) : const Value.absent(),
          enabled: enabled != null ? Value(enabled) : const Value.absent(),
        ),
      );

  /// Unlink all books, then delete the connection row.
  Future<void> delete(int id) async {
    await (_db.update(
      _db.books,
    )..where((t) => t.serverConnectionId.equals(id))).write(
      const BooksCompanion(
        serverConnectionId: Value(null),
        remoteIds: Value(null),
        lastSyncedAt: Value(null),
      ),
    );
    await (_db.delete(
      _db.serverConnections,
    )..where((t) => t.id.equals(id))).go();
  }

  /// Link a local book to a server book. Metadata-only: never touches the
  /// book's files or reading data.
  Future<void> linkBook(
    int bookId,
    int connectionId,
    Map<String, String> remoteIds,
  ) => (_db.update(_db.books)..where((t) => t.id.equals(bookId))).write(
    BooksCompanion(
      serverConnectionId: Value(connectionId),
      remoteIds: Value(jsonEncode(remoteIds)),
    ),
  );

  Future<List<Book>> booksLinkedTo(int connectionId) => (_db.select(
    _db.books,
  )..where((t) => t.serverConnectionId.equals(connectionId))).get();

  /// The local book already linked to the server book identified by [ids],
  /// or null. Identity is the primary remote id.
  Future<Book?> findLinkedBook(
    int connectionId,
    Map<String, String> ids,
  ) async {
    final primary = primaryRemoteId(ids);
    if (primary == null) return null;
    for (final book in await booksLinkedTo(connectionId)) {
      final stored = decodeRemoteIds(book.remoteIds);
      if (stored != null && primaryRemoteId(stored) == primary) return book;
    }
    return null;
  }

  /// An unlinked local book of [bookType] whose title matches [title]
  /// (trim+lowercase, same normalization as backup matching), or null.
  Future<Book?> findUnlinkedTitleMatch(String title, String bookType) async {
    final normalized = title.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    final candidates =
        await (_db.select(_db.books)..where(
              (t) =>
                  t.serverConnectionId.isNull() & t.bookType.equals(bookType),
            ))
            .get();
    for (final book in candidates) {
      if (book.title.trim().toLowerCase() == normalized) return book;
    }
    return null;
  }

  /// The primary remote id of a `RemoteBook.ids` bundle (Komga `bookId`,
  /// Kavita `chapterId`).
  static String? primaryRemoteId(Map<String, String> ids) =>
      ids['bookId'] ?? ids['chapterId'];

  /// Decode a `Books.remoteIds` JSON string; null when absent or malformed.
  static Map<String, String>? decodeRemoteIds(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      return (jsonDecode(json) as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, '$value'),
      );
    } catch (_) {
      return null;
    }
  }
}
