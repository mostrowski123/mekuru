import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/library/data/models/book.dart';
import '../../features/vocabulary/data/models/saved_word.dart';
import '../../features/dictionary/data/models/dictionary_meta.dart';
import '../../features/dictionary/data/models/dictionary_entry.dart';
import '../../features/dictionary/data/models/pitch_accent.dart';
import '../../features/dictionary/data/models/frequency.dart';

part 'database_provider.g.dart';

@DriftDatabase(tables: [Books, SavedWords, DictionaryMetas, DictionaryEntries, PitchAccents, Frequencies])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 9;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (migrator, from, to) async {
          if (from < 2) {
            await migrator.addColumn(
              dictionaryMetas,
              dictionaryMetas.sortOrder,
            );
            // Preserve existing display order by using insertion id
            await customStatement(
              'UPDATE dictionary_metas SET sort_order = id',
            );
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
            await migrator.addColumn(
              dictionaryMetas,
              dictionaryMetas.isHidden,
            );
            // Hide existing bundled JPDB frequency dictionary
            await customStatement(
              "UPDATE dictionary_metas SET is_hidden = 1 WHERE name = 'JPDBv2\u32D5'",
            );
          }
          if (from < 8) {
            await migrator.addColumn(books, books.language);
            await migrator.addColumn(
              books,
              books.pageProgressionDirection,
            );
          }
          if (from < 9) {
            await migrator.addColumn(books, books.overrideVerticalText);
            await migrator.addColumn(books, books.overrideReadingDirection);
          }
        },
      );

  static QueryExecutor _openConnection() {
    return driftDatabase(
      name: 'mekuru_db',
      native: DriftNativeOptions(
        databaseDirectory: getApplicationSupportDirectory,
      ),
    );
  }
}
