import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/backup/data/models/backup_manifest.dart';
import 'package:mekuru/features/backup/data/services/book_match_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reads the current app state (DB + SharedPreferences) and produces
/// a [BackupManifest] ready for serialization.
class BackupService {
  final AppDatabase _db;
  final BookMatchService _bookMatchService;

  BackupService(this._db, this._bookMatchService);

  /// All app.* SharedPreferences keys to include in backup.
  static const _appKeys = [
    'app.theme_mode',
    'app.library_sort_order',
    'app.lookup_font_size',
    'app.dictionary_search_history',
    'app.filter_roman_letters',
    'app.ankidroid_config',
    'app.startup_screen',
    'app.auto_focus_search',
    'app.color_theme',
    'app.auto_crop_white_threshold',
    'app.ocr_server_url',
    'app.manga_lookup_overrides',
    'backup.auto_interval',
  ];

  /// All reader.* SharedPreferences keys to include in backup.
  static const _readerKeys = [
    'reader.font_size',
    'reader.page_turn_animation',
    'reader.horizontal_padding',
    'reader.vertical_padding',
    'reader.swipe_sensitivity',
    'reader.color_mode',
    'reader.keep_screen_on',
    'reader.sepia_intensity',
    'reader.disable_links',
  ];

  Future<BackupManifest> createBackup() async {
    final prefs = await SharedPreferences.getInstance();

    final appSettings = _readPrefsMap(prefs, _appKeys);
    final readerSettings = _readPrefsMap(prefs, _readerKeys);

    final savedWords = await _db.select(_db.savedWords).get();
    final books = await _db.select(_db.books).get();

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
