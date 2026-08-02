import 'package:drift/drift.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/backup/data/models/backup_manifest.dart';
import 'package:mekuru/features/backup/data/services/backup_scheduler.dart';
import 'package:mekuru/features/backup/data/services/book_match_service.dart';
import 'package:mekuru/features/manga/data/services/manga_lookup_override_storage.dart';
import 'package:mekuru/features/reader/data/services/reader_settings_storage.dart';
import 'package:mekuru/features/settings/data/services/app_settings_storage.dart';
import 'package:mekuru/features/stats/data/repositories/stats_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reads the current app state (DB + SharedPreferences) and produces
/// a [BackupManifest] ready for serialization.
class BackupService {
  final AppDatabase _db;
  final BookMatchService _bookMatchService;

  BackupService(this._db, this._bookMatchService);

  /// All app-level SharedPreferences keys to include in backup, derived from
  /// the storage classes that own them so new settings are picked up
  /// automatically.
  static const List<String> appKeys = [
    ...SharedPreferencesAppSettingsStorage.allKeys,
    MangaLookupOverrideStorage.prefsKey,
    BackupScheduler.intervalKey,
  ];

  /// All reader.* SharedPreferences keys to include in backup.
  static const List<String> readerKeys =
      SharedPreferencesReaderSettingsStorage.allKeys;

  Future<BackupManifest> createBackup() async {
    final prefs = await SharedPreferences.getInstance();

    final appSettings = _readPrefsMap(prefs, appKeys);
    final readerSettings = _readPrefsMap(prefs, readerKeys);
    final dictionaryPreferences =
        await (_db.select(_db.dictionaryMetas)
              ..where((t) => t.isHidden.equals(false))
              ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
            .get();

    final savedWords = await _db.select(_db.savedWords).get();
    final books = await _db.select(_db.books).get();

    final statsRepository = StatsRepository(_db);
    final readingSessions = await statsRepository.getAllSessions();
    final wordEvents = await statsRepository.getAllWordEvents();

    final bookEntries = <BackupBookEntry>[];
    for (final book in books) {
      final bookKey = await _bookMatchService.generatePreferredKey(
        book.title,
        book.bookType,
        book.filePath,
      );

      final bookmarks = await (_db.select(
        _db.bookmarks,
      )..where((t) => t.bookId.equals(book.id))).get();

      final highlights = await (_db.select(
        _db.highlights,
      )..where((t) => t.bookId.equals(book.id))).get();

      bookEntries.add(
        BackupBookEntry(
          bookKey: bookKey,
          title: book.title,
          bookType: book.bookType,
          language: book.language,
          pageProgressionDirection: book.pageProgressionDirection,
          primaryWritingMode: book.primaryWritingMode,
          lastReadCfi: book.lastReadCfi,
          readProgress: book.readProgress,
          lastReadAt: book.lastReadAt,
          overrideVerticalText: book.overrideVerticalText,
          overrideReadingDirection: book.overrideReadingDirection,
          bookmarks: bookmarks
              .map(
                (bm) => BackupBookmarkEntry(
                  cfi: bm.cfi,
                  progress: bm.progress,
                  chapterTitle: bm.chapterTitle,
                  userNote: bm.userNote,
                  dateAdded: bm.dateAdded,
                ),
              )
              .toList(),
          highlights: highlights
              .map(
                (hl) => BackupHighlightEntry(
                  cfiRange: hl.cfiRange,
                  selectedText: hl.selectedText,
                  color: hl.color,
                  userNote: hl.userNote,
                  dateAdded: hl.dateAdded,
                ),
              )
              .toList(),
        ),
      );
    }

    return BackupManifest(
      version: BackupManifest.currentVersion,
      createdAt: DateTime.now().toUtc(),
      settings: BackupSettings(app: appSettings, reader: readerSettings),
      dictionaryPreferences: dictionaryPreferences
          .map(
            (dictionary) => BackupDictionaryPreference(
              name: dictionary.name,
              sortOrder: dictionary.sortOrder,
              isEnabled: dictionary.isEnabled,
            ),
          )
          .toList(growable: false),
      savedWords: savedWords
          .map(
            (w) => BackupSavedWordEntry(
              expression: w.expression,
              reading: w.reading,
              glossaries: w.glossaries,
              sentenceContext: w.sentenceContext,
              dateAdded: w.dateAdded,
            ),
          )
          .toList(),
      books: bookEntries,
      readingSessions: readingSessions
          .map(
            (s) => BackupReadingSessionEntry(
              bookId: s.bookId,
              bookFormat: s.bookFormat,
              startedAt: s.startedAt,
              durationMs: s.durationMs,
              pagesTurned: s.pagesTurned,
              charactersRead: s.charactersRead,
              lookups: s.lookups,
              wordsSaved: s.wordsSaved,
            ),
          )
          .toList(),
      wordEvents: wordEvents
          .map(
            (e) => BackupWordEventEntry(
              kind: e.kind,
              expression: e.expression,
              source: e.source,
              createdAt: e.createdAt,
            ),
          )
          .toList(),
    );
  }

  Map<String, dynamic> _readPrefsMap(
    SharedPreferences prefs,
    List<String> keys,
  ) {
    final map = <String, dynamic>{};
    for (final key in keys) {
      final value = prefs.get(key);
      if (value != null) {
        map[key] = value;
      }
    }
    return map;
  }
}
