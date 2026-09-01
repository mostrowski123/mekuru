import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/sync/data/models/remote_models.dart';
import 'package:mekuru/features/sync/data/repositories/server_connection_repository.dart';

import 'server_client.dart';

/// Builds a client for a connection (async: credentials load from secure
/// storage); injectable so tests can fake servers.
typedef ServerClientFactory =
    Future<ServerClient> Function(ServerConnection connection);

/// Bidirectional progress sync for server-linked books.
///
/// Rules (deliberately simple — progress can be delayed, never lost):
/// - A local progress write schedules a debounced fire-and-forget push.
/// - On book open: push local first when it is newer than the last sync,
///   then pull; the remote result is applied only when its timestamp is
///   strictly newer than the local one. Timestamps come from two different
///   clocks (server vs device) — accepted limitation, the same one every
///   sync client of these servers lives with.
/// - Failures are swallowed after logging: the next write or open retries.
class ProgressSyncService {
  final AppDatabase _db;
  final ServerConnectionRepository _connections;
  final ServerClientFactory _clientFactory;
  final Duration pushDebounce;

  final Map<int, Timer> _pushTimers = {};
  final Map<int, ServerClient> _clients = {};
  StreamSubscription<List<ServerConnection>>? _connectionsSub;
  bool _applyingRemote = false;
  bool _disposed = false;

  ProgressSyncService({
    required AppDatabase db,
    required ServerConnectionRepository connections,
    required ServerClientFactory clientFactory,
    this.pushDebounce = const Duration(seconds: 2),
  }) : _db = db,
       _connections = connections,
       _clientFactory = clientFactory {
    // Connection edits (URL/credentials) invalidate cached clients.
    _connectionsSub = _connections.watchConnections().listen((_) {
      for (final client in _clients.values) {
        client.dispose();
      }
      _clients.clear();
    });
  }

  void dispose() {
    _disposed = true;
    _connectionsSub?.cancel();
    for (final timer in _pushTimers.values) {
      timer.cancel();
    }
    _pushTimers.clear();
    for (final client in _clients.values) {
      client.dispose();
    }
    _clients.clear();
  }

  /// Debounced fire-and-forget push, hooked to BookRepository progress
  /// writes. No-ops while a pulled remote state is being applied.
  void schedulePush(int bookId) {
    if (_disposed || _applyingRemote) return;
    _pushTimers[bookId]?.cancel();
    _pushTimers[bookId] = Timer(pushDebounce, () {
      _pushTimers.remove(bookId);
      pushBook(bookId).catchError((Object e) {
        debugPrint('[Sync] push failed for book $bookId: $e');
      });
    });
  }

  /// Push the book's current progress to its server, if linked and enabled.
  Future<void> pushBook(int bookId) async {
    final book = await _bookById(bookId);
    if (book == null) return;
    final link = await _linkFor(book);
    if (link == null) return;
    final progress = _localProgress(book);
    if (progress == null) return;
    await link.client.pushProgress(link.ids, progress);
    await _markSynced(bookId);
  }

  /// Sync at book-open time: push a newer local state first, then pull.
  ///
  /// Returns the remote progress when it was strictly newer and has been
  /// persisted locally — the caller may additionally move the open reader
  /// to it. Returns null (silently, logging only) on any failure.
  Future<RemoteProgress?> syncOnOpen(Book book) async {
    try {
      final link = await _linkFor(book);
      if (link == null) return null;

      final localNewer =
          book.lastReadAt != null &&
          (book.lastSyncedAt == null ||
              book.lastReadAt!.isAfter(book.lastSyncedAt!));
      if (localNewer) {
        final progress = _localProgress(book);
        if (progress != null) {
          await link.client.pushProgress(link.ids, progress);
          await _markSynced(book.id);
        }
      }

      final remote = await link.client.pullProgress(link.ids);
      if (remote == null) return null;

      // Local wins unless the remote record is strictly newer.
      final localAt = book.lastReadAt;
      if (localAt != null &&
          (remote.lastModified == null ||
              !remote.lastModified!.isAfter(localAt))) {
        await _markSynced(book.id);
        return null;
      }

      await _applyRemote(book, remote);
      await _markSynced(book.id);
      return remote;
    } on SyncException catch (e) {
      debugPrint('[Sync] syncOnOpen failed: $e');
      return null;
    }
  }

  /// [syncOnOpen] by book id — for callers that only hold an id (e.g. the
  /// bulk link flow's one-time sync of freshly linked books).
  Future<RemoteProgress?> syncBookById(int bookId) async {
    final book = await _bookById(bookId);
    if (book == null) return null;
    return syncOnOpen(book);
  }

  /// Push every linked book of every enabled connection whose local state
  /// is newer than its last sync. Returns (pushed, failed) counts.
  Future<({int pushed, int failed})> syncAll() async {
    var pushed = 0;
    var failed = 0;
    final connections = await _connections.watchConnections().first;
    for (final connection in connections.where((c) => c.enabled)) {
      final books = await _connections.booksLinkedTo(connection.id);
      for (final book in books) {
        final upToDate =
            book.lastReadAt == null ||
            (book.lastSyncedAt != null &&
                !book.lastReadAt!.isAfter(book.lastSyncedAt!));
        if (upToDate) continue;
        try {
          await pushBook(book.id);
          pushed++;
        } on SyncException catch (e) {
          debugPrint('[Sync] syncAll push failed: $e');
          failed++;
        }
      }
    }
    return (pushed: pushed, failed: failed);
  }

  // ──────────────── internals ────────────────

  Future<Book?> _bookById(int id) =>
      (_db.select(_db.books)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<({ServerClient client, Map<String, String> ids})?> _linkFor(
    Book book,
  ) async {
    final connectionId = book.serverConnectionId;
    final ids = ServerConnectionRepository.decodeRemoteIds(book.remoteIds);
    if (connectionId == null || ids == null) return null;
    var client = _clients[connectionId];
    if (client == null) {
      final connection = await _connections.getById(connectionId);
      if (connection == null || !connection.enabled) return null;
      client = await _clientFactory(connection);
      _clients[connectionId] = client;
    }
    return (client: client, ids: ids);
  }

  /// The book's local progress as a [RemoteProgress], or null when there is
  /// nothing meaningful to push yet.
  RemoteProgress? _localProgress(Book book) {
    final completed = book.readProgress >= 0.995;
    if (book.bookType == 'manga') {
      final cfi = book.lastReadCfi ?? '';
      // Scroll mode stores 'scroll:<px>' — approximate via readProgress.
      final page = cfi.startsWith('scroll:')
          ? (book.totalPages > 1
                ? (book.readProgress * (book.totalPages - 1)).round()
                : null)
          : int.tryParse(cfi);
      if (page == null || (page <= 0 && !completed)) return null;
      return RemoteProgress(
        page: page,
        completed: completed,
        totalProgression: book.readProgress.clamp(0.0, 1.0),
      );
    }
    if (book.lastReadHref == null && book.readProgress <= 0) return null;
    return RemoteProgress(
      href: book.lastReadHref,
      progression: book.lastReadProgression,
      totalProgression: book.readProgress.clamp(0.0, 1.0),
      completed: completed,
    );
  }

  /// Persist a newer remote state. Writes progress fields only — never
  /// lastReadAt (so this apply can't masquerade as local reading) and, for
  /// EPUBs, never the CFI (the on-open jump uses totalProgression; a stale
  /// CFI is still the best offline fallback).
  Future<void> _applyRemote(Book book, RemoteProgress remote) async {
    _applyingRemote = true;
    try {
      if (book.bookType == 'manga' && remote.page != null) {
        final page = remote.page!.clamp(
          0,
          book.totalPages > 0 ? book.totalPages - 1 : remote.page!,
        );
        final progress = book.totalPages > 1
            ? page / (book.totalPages - 1)
            : (remote.completed ? 1.0 : 0.0);
        await (_db.update(_db.books)..where((t) => t.id.equals(book.id))).write(
          BooksCompanion(
            lastReadCfi: Value('$page'),
            readProgress: Value(progress.clamp(0.0, 1.0)),
          ),
        );
        return;
      }
      final total = remote.totalProgression;
      if (book.bookType == 'epub' && total != null) {
        await (_db.update(_db.books)..where((t) => t.id.equals(book.id))).write(
          BooksCompanion(
            readProgress: Value(total.clamp(0.0, 1.0)),
            lastReadHref: remote.href != null
                ? Value(remote.href)
                : const Value.absent(),
            lastReadProgression: remote.progression != null
                ? Value(remote.progression)
                : const Value.absent(),
          ),
        );
      }
    } finally {
      _applyingRemote = false;
    }
  }

  Future<void> _markSynced(int bookId) =>
      (_db.update(_db.books)..where((t) => t.id.equals(bookId))).write(
        BooksCompanion(lastSyncedAt: Value(DateTime.now())),
      );
}
