import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/library/data/models/book.dart';
import '../../features/vocabulary/data/models/saved_word.dart';
import '../../features/dictionary/data/models/dictionary_meta.dart';
import '../../features/dictionary/data/models/dictionary_entry.dart';
import '../../features/dictionary/data/models/pitch_accent.dart';
import '../../features/dictionary/data/models/frequency.dart';
import '../../features/reader/data/models/bookmark.dart';
import '../../features/reader/data/models/highlight.dart';
import '../../features/backup/data/models/pending_book_data.dart';

part 'database_provider.g.dart';

@DriftDatabase(
  tables: [
    Books,
    SavedWords,
    DictionaryMetas,
    DictionaryEntries,
    PitchAccents,
    Frequencies,
    Bookmarks,
    Highlights,
    PendingBookDatas,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  static const Map<String, String> _dictionaryEntriesRepairColumns = {
    'entry_kind':
        "ALTER TABLE dictionary_entries ADD COLUMN entry_kind TEXT NOT NULL DEFAULT 'regular'",
    'kanji_onyomi':
        "ALTER TABLE dictionary_entries ADD COLUMN kanji_onyomi TEXT NOT NULL DEFAULT ''",
    'kanji_kunyomi':
        "ALTER TABLE dictionary_entries ADD COLUMN kanji_kunyomi TEXT NOT NULL DEFAULT ''",
    'definition_tags':
        "ALTER TABLE dictionary_entries ADD COLUMN definition_tags TEXT NOT NULL DEFAULT ''",
    'rules':
        "ALTER TABLE dictionary_entries ADD COLUMN rules TEXT NOT NULL DEFAULT ''",
    'term_tags':
        "ALTER TABLE dictionary_entries ADD COLUMN term_tags TEXT NOT NULL DEFAULT ''",
  };

  @override
  int get schemaVersion => 16;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.addColumn(dictionaryMetas, dictionaryMetas.sortOrder);
        // Preserve existing display order by using insertion id
        await customStatement('UPDATE dictionary_metas SET sort_order = id');
      }
      if (from < 3) {
        await migrator.addColumn(books, books.readProgress);
      }
      if (from < 4) {
        await migrator.addColumn(books, books.lastReadAt);
      }
      if (from < 5) {
        await migrator.createTable(pitchAccents);
      }
      if (from < 6) {
        await migrator.createTable(frequencies);
      }
      if (from < 7) {
        await migrator.addColumn(dictionaryMetas, dictionaryMetas.isHidden);
        // Hide existing bundled JPDB frequency dictionary
        await customStatement(
          "UPDATE dictionary_metas SET is_hidden = 1 WHERE name = 'JPDBv2\u32D5'",
        );
      }
      if (from < 8) {
        await migrator.addColumn(books, books.language);
        await migrator.addColumn(books, books.pageProgressionDirection);
      }
      if (from < 9) {
        await migrator.addColumn(books, books.overrideVerticalText);
        await migrator.addColumn(books, books.overrideReadingDirection);
      }
      if (from < 10) {
        await migrator.createTable(bookmarks);
        await migrator.createTable(highlights);
      }
      if (from < 11) {
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_expr_dictid ON dictionary_entries (expression, dictionary_id)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_read_dictid ON dictionary_entries (reading, dictionary_id)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_freq_expr_read ON frequencies (expression, reading)',
        );
      }
      if (from < 12) {
        await migrator.addColumn(books, books.bookType);
      }
      if (from < 13) {
        await migrator.createTable(pendingBookDatas);
      }
      if (from < 14) {
        await migrator.addColumn(
          dictionaryEntries,
          dictionaryEntries.entryKind,
        );
        await migrator.addColumn(
          dictionaryEntries,
          dictionaryEntries.kanjiOnyomi,
        );
        await migrator.addColumn(
          dictionaryEntries,
          dictionaryEntries.kanjiKunyomi,
        );
      }
      if (from < 15) {
        await migrator.addColumn(
          dictionaryEntries,
          dictionaryEntries.definitionTags,
        );
        await migrator.addColumn(dictionaryEntries, dictionaryEntries.rules);
        await migrator.addColumn(dictionaryEntries, dictionaryEntries.termTags);
      }
      if (from < 16) {
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_pitch_expr_dictid ON pitch_accents (expression, dictionary_id)',
        );
      }
    },
    beforeOpen: (details) async {
      await _repairDictionaryEntriesSchemaIfNeeded();
    },
  );

  Future<void> _repairDictionaryEntriesSchemaIfNeeded() async {
    final tableRows = await customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'dictionary_entries'",
    ).get();
    if (tableRows.isEmpty) return;

    final pragmaRows = await customSelect(
      "PRAGMA table_info('dictionary_entries')",
    ).get();
    final existingColumns = pragmaRows
        .map((row) => row.data['name']?.toString())
        .whereType<String>()
        .toSet();

    for (final entry in _dictionaryEntriesRepairColumns.entries) {
      if (!existingColumns.contains(entry.key)) {
        await customStatement(entry.value);
      }
    }
  }

  static QueryExecutor _openConnection() {
    return driftDatabase(
      name: 'mekuru_db',
      native: DriftNativeOptions(
        databaseDirectory: getApplicationSupportDirectory,
      ),
    );
  }
}
