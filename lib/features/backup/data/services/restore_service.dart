import 'package:drift/drift.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/backup/data/models/backup_manifest.dart';
import 'package:mekuru/features/backup/data/models/pending_dictionary_restore.dart';
import 'package:mekuru/features/backup/data/repositories/pending_book_data_repository.dart';
import 'package:mekuru/features/backup/data/services/backup_serializer.dart';
import 'package:mekuru/features/backup/data/services/book_match_service.dart';
import 'package:mekuru/features/settings/data/services/app_settings_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Result of a full restore operation.
class RestoreResult {
  final bool settingsRestored;
  final RestoreDictionaryPreferencesResult dictionaryPreferencesResult;
  final RestoreWordResult wordsResult;
  final RestoreBookResult booksResult;
  final List<String> errors;

  const RestoreResult({
    required this.settingsRestored,
    this.dictionaryPreferencesResult =
        const RestoreDictionaryPreferencesResult(),
    required this.wordsResult,
    required this.booksResult,
    this.errors = const [],
  });
}

/// Result of restoring saved words.
class RestoreWordResult {
  final int added;
  final int skipped;

  const RestoreWordResult({required this.added, required this.skipped});
}

/// Result of restoring book data.
class RestoreBookResult {
  final int applied;
  final int pending;
  final List<BookRestoreConflict> conflicts;

  const RestoreBookResult({
    required this.applied,
    required this.pending,
    required this.conflicts,
  });
}

/// A book that exists in both backup and library with existing user data.
class BookRestoreConflict {
  final BackupBookEntry backupEntry;
  final Book existingBook;

  const BookRestoreConflict({
    required this.backupEntry,
    required this.existingBook,
  });
}

/// Orchestrates restoring from a [BackupManifest].
class RestoreService {
  final AppDatabase _db;
  final BookMatchService _bookMatchService;
  final PendingBookDataRepository _pendingRepo;

  RestoreService(this._db, this._bookMatchService, this._pendingRepo);

  /// Restore all settings from backup.
  Future<bool> restoreSettings(BackupManifest manifest) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      for (final entry in manifest.settings.app.entries) {
        await _writePrefsValue(prefs, entry.key, entry.value);
      }
      for (final entry in manifest.settings.reader.entries) {
        await _writePrefsValue(prefs, entry.key, entry.value);
      }

      _syncPreloadedThemeSettings(manifest.settings.app);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Restore saved words, merging by expression+reading (skip duplicates).
  Future<RestoreWordResult> restoreSavedWords(BackupManifest manifest) async {
    int added = 0;
    int skipped = 0;

    for (final word in manifest.savedWords) {
      final existing =
          await (_db.select(_db.savedWords)..where(
                (t) =>
                    t.expression.equals(word.expression) &
                    t.reading.equals(word.reading),
              ))
              .getSingleOrNull();

      if (existing != null) {
        skipped++;
        continue;
      }

      await _db
          .into(_db.savedWords)
          .insert(
            SavedWordsCompanion.insert(
              expression: word.expression,
              reading: Value(word.reading),
              glossaries: word.glossaries,
              sentenceContext: Value(word.sentenceContext),
              dateAdded: Value(word.dateAdded),
            ),
          );
      added++;
    }

    return RestoreWordResult(added: added, skipped: skipped);
  }

  /// Restore reading statistics.
  ///
  /// Reading sessions are filled only when the table is still empty locally:
  /// interleaving two devices' session histories was judged riskier than
  /// preserving whichever history the device already has, and no migration
  /// ever backfills sessions, so the empty check is a faithful "this device
  /// has no history yet" signal. Word events don't get that luxury — the v19
  /// upgrade backfills them from saved_words, so the table is almost never
  /// empty on an upgraded install — and they carry a usable identity
  /// (kind + expression + source + createdAt), so they are merged instead:
  /// backup events not already present locally are inserted. Both paths keep
  /// a repeated restore a no-op. `bookId` is written verbatim: it is display
  /// metadata and is never joined against Books.
  Future<void> restoreStats(BackupManifest manifest) async {
    await _fillIfEmpty(
      _db.readingSessions,
      manifest.readingSessions
          .map(
            (s) => ReadingSessionsCompanion.insert(
              bookId: Value(s.bookId),
              bookFormat: s.bookFormat,
              startedAt: s.startedAt,
              durationMs: s.durationMs,
              pagesTurned: Value(s.pagesTurned),
              charactersRead: Value(s.charactersRead),
              lookups: Value(s.lookups),
              wordsSaved: Value(s.wordsSaved),
            ),
          )
          .toList(),
    );

    await _mergeWordEvents(manifest.wordEvents);
  }

  /// Inserts the backup's word events that are not already present locally.
  ///
  /// Identity is (kind, expression, source, createdAt), compared on the epoch
  /// instant — local rows come back from Drift in local time while backup
  /// entries parse as UTC, and DateTime's == is zone-sensitive. Duplicate
  /// counting is harmless to the charts (they dedupe by expression), but
  /// skipping exact duplicates keeps repeated restores from growing the
  /// table.
  Future<void> _mergeWordEvents(List<BackupWordEventEntry> events) async {
    if (events.isEmpty) return;

    // One key builder for both row types keeps the two sides congruent.
    (String, String, String, int) key(
      String kind,
      String expression,
      String source,
      DateTime createdAt,
    ) => (kind, expression, source, createdAt.millisecondsSinceEpoch);

    final seen = {
      for (final e in await _db.select(_db.wordEvents).get())
        key(e.kind, e.expression, e.source, e.createdAt),
    };
    final toInsert = [
      for (final e in events)
        if (seen.add(key(e.kind, e.expression, e.source, e.createdAt)))
          WordEventsCompanion.insert(
            kind: e.kind,
            expression: e.expression,
            source: Value(e.source),
            // Explicit: the column defaults to now(), which would
            // rewrite every restored event to the restore time.
            createdAt: Value(e.createdAt),
          ),
    ];
    if (toInsert.isEmpty) return;
    await _db.batch((batch) => batch.insertAll(_db.wordEvents, toInsert));
  }

  /// Batch-inserts [rows] into [table], but only when the table is still
  /// untouched.
  ///
  /// Reading sessions are restored all-or-nothing: a device that has already
  /// recorded sessions of its own keeps them, rather than ending up with a
  /// backup's history interleaved into it.
  Future<void> _fillIfEmpty<T extends Table, D>(
    TableInfo<T, D> table,
    List<Insertable<D>> rows,
  ) async {
    if (rows.isEmpty) return;
    final existing = await (_db.select(table)..limit(1)).get();
    if (existing.isNotEmpty) return;
    await _db.batch((batch) => batch.insertAll(table, rows));
  }

  /// Restore book data. Returns conflicts for the UI to resolve.
  Future<RestoreBookResult> restoreBooks(BackupManifest manifest) async {
    final existingBooks = await _db.select(_db.books).get();
    final hasHashKeys = manifest.books.any(
      (entry) => _bookMatchService.isHashKey(entry.bookKey),
    );
    final hashIndex = hasHashKeys
        ? await _bookMatchService.buildHashIndex(existingBooks)
        : const <String, Book>{};

    final conflicts = <BookRestoreConflict>[];
    int applied = 0;
    int pending = 0;

    for (final entry in manifest.books) {
      final match = _bookMatchService.isHashKey(entry.bookKey)
          ? hashIndex[entry.bookKey]
          : _bookMatchService.findLegacyMatch(entry.bookKey, existingBooks);

      if (match != null) {
        final hasData = await _bookHasUserData(match);
        if (hasData) {
          conflicts.add(
            BookRestoreConflict(backupEntry: entry, existingBook: match),
          );
        } else {
          await applyBookData(match.id, entry);
          applied++;
        }
      } else {
        await _pendingRepo.insert(
          entry.bookKey,
          BackupSerializer.encodeBookEntry(entry),
        );
        pending++;
      }
    }

    return RestoreBookResult(
      applied: applied,
      pending: pending,
      conflicts: conflicts,
    );
  }

  /// Apply backup data to a specific book. Used for conflicts and pending data.
  Future<void> applyBookData(int bookId, BackupBookEntry entry) async {
    // Update reading progress and overrides
    await (_db.update(_db.books)..where((t) => t.id.equals(bookId))).write(
      BooksCompanion(
        lastReadCfi: Value(entry.lastReadCfi),
        readProgress: Value(entry.readProgress),
        lastReadAt: Value(entry.lastReadAt),
        overrideVerticalText: Value(entry.overrideVerticalText),
        overrideReadingDirection: Value(entry.overrideReadingDirection),
      ),
    );

    // Insert bookmarks, skip duplicates by CFI
    for (final bm in entry.bookmarks) {
      final existing =
          await (_db.select(_db.bookmarks)
                ..where((t) => t.bookId.equals(bookId) & t.cfi.equals(bm.cfi)))
              .getSingleOrNull();

      if (existing == null) {
        await _db
            .into(_db.bookmarks)
            .insert(
              BookmarksCompanion.insert(
                bookId: bookId,
                cfi: bm.cfi,
                progress: Value(bm.progress),
                chapterTitle: Value(bm.chapterTitle),
                userNote: Value(bm.userNote),
                dateAdded: Value(bm.dateAdded),
              ),
            );
      }
    }

    // Insert highlights, skip duplicates by cfiRange
    for (final hl in entry.highlights) {
      final existing =
          await (_db.select(_db.highlights)..where(
                (t) => t.bookId.equals(bookId) & t.cfiRange.equals(hl.cfiRange),
              ))
              .getSingleOrNull();

      if (existing == null) {
        await _db
            .into(_db.highlights)
            .insert(
              HighlightsCompanion.insert(
                bookId: bookId,
                cfiRange: hl.cfiRange,
                selectedText: hl.selectedText,
                color: Value(hl.color),
                userNote: Value(hl.userNote),
                dateAdded: Value(hl.dateAdded),
              ),
            );
      }
    }
  }

  /// Check if a book has user-generated data (progress, bookmarks, highlights).
  Future<bool> _bookHasUserData(Book book) async {
    if (book.readProgress > 0 || book.lastReadCfi != null) return true;

    final bookmarkCount = await (_db.select(
      _db.bookmarks,
    )..where((t) => t.bookId.equals(book.id))).get();
    if (bookmarkCount.isNotEmpty) return true;

    final highlightCount = await (_db.select(
      _db.highlights,
    )..where((t) => t.bookId.equals(book.id))).get();
    return highlightCount.isNotEmpty;
  }

  void _syncPreloadedThemeSettings(Map<String, dynamic> appSettings) {
    final themeMode = appSettings['app.theme_mode'];
    if (themeMode is String) {
      PreloadedAppSettings.setThemeModeFromName(themeMode);
    }

    final colorTheme = appSettings['app.color_theme'];
    if (colorTheme is String) {
      PreloadedAppSettings.setColorThemeName(colorTheme);
    }
  }

  Future<void> _writePrefsValue(
    SharedPreferences prefs,
    String key,
    dynamic value,
  ) async {
    if (value is String) {
      await prefs.setString(key, value);
    } else if (value is int) {
      await prefs.setInt(key, value);
    } else if (value is double) {
      await prefs.setDouble(key, value);
    } else if (value is bool) {
      await prefs.setBool(key, value);
    }
  }
}
