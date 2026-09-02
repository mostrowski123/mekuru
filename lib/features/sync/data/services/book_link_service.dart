import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/backup/data/services/book_match_service.dart';

import '../models/remote_models.dart';
import '../repositories/server_connection_repository.dart';
import 'server_client.dart';

/// Bulk-links existing local books to their copies on a server so their
/// progress can sync — the "push existing data" path.
///
/// Matching is by normalized title (trim + lowercase, the backup-matching
/// normalization) against each remote book's title and its
/// "series title + title", same book type. Ambiguous titles (two remote
/// books sharing a key) are never auto-linked; the browse screen's
/// link-instead-of-download dialog is the manual fallback for those.
/// Linking writes only the link columns — never files or reading data.
class BookLinkService {
  final AppDatabase _db;
  final ServerConnectionRepository _connections;

  /// Series whose books are listed concurrently per round trip.
  static const _batchSize = 4;

  BookLinkService(this._db, this._connections);

  Future<({List<int> linkedBookIds, int unmatched})> linkExistingBooks(
    ServerConnection connection,
    ServerClient client,
  ) async {
    // Index the server catalog. A key claimed by two different remote books
    // becomes null — ambiguous, skip.
    final remoteByKey = <String, RemoteBook?>{};
    void index(RemoteBook book) {
      final keys = {
        BookMatchService.normalizeTitle(book.title),
        BookMatchService.normalizeTitle('${book.seriesTitle} ${book.title}'),
      }..remove('');
      for (final key in keys) {
        remoteByKey[key] = remoteByKey.containsKey(key) ? null : book;
      }
    }

    for (final library in await client.listLibraries()) {
      final seriesList = await client.listSeries(library.id);
      // ponytail: fixed-size batches, not a pool — one slow series holds its
      // batch; switch to a real pool if link time still matters.
      for (var i = 0; i < seriesList.length; i += _batchSize) {
        final batch = seriesList.skip(i).take(_batchSize);
        for (final books in await Future.wait(batch.map(client.listBooks))) {
          books.forEach(index);
        }
      }
    }

    // Remote books already claimed by a local book must not be linked twice.
    final claimed = <String>{};
    for (final book in await _connections.booksLinkedTo(connection.id)) {
      final ids = ServerConnectionRepository.decodeRemoteIds(book.remoteIds);
      final primary = ids == null
          ? null
          : ServerConnectionRepository.primaryRemoteId(ids);
      if (primary != null) claimed.add(primary);
    }

    final unlinked = await (_db.select(
      _db.books,
    )..where((t) => t.serverConnectionId.isNull())).get();

    final linkedBookIds = <int>[];
    var unmatched = 0;
    for (final book in unlinked) {
      final candidate =
          remoteByKey[BookMatchService.normalizeTitle(book.title)];
      final primary = candidate == null
          ? null
          : ServerConnectionRepository.primaryRemoteId(candidate.ids);
      final localIsEpub = book.bookType == 'epub';
      final usable =
          candidate != null &&
          primary != null &&
          !claimed.contains(primary) &&
          (candidate.format == RemoteBookFormat.epub) == localIsEpub;
      if (!usable) {
        unmatched++;
        continue;
      }
      await _connections.linkBook(book.id, connection.id, candidate.ids);
      claimed.add(primary);
      linkedBookIds.add(book.id);
    }
    return (linkedBookIds: linkedBookIds, unmatched: unmatched);
  }
}
