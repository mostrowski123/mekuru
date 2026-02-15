import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/library/data/models/book.dart';
import '../../features/vocabulary/data/models/saved_word.dart';
import '../../features/dictionary/data/models/dictionary_meta.dart';
import '../../features/dictionary/data/models/dictionary_entry.dart';

part 'database_provider.g.dart';

@DriftDatabase(tables: [Books, SavedWords, DictionaryMetas, DictionaryEntries])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 1;

  static QueryExecutor _openConnection() {
    return driftDatabase(
      name: 'mekuru_db',
      native: DriftNativeOptions(
        databaseDirectory: getApplicationSupportDirectory,
      ),
    );
  }
}
