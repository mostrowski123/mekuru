/// Shared assertions/fixtures for the glossary FTS index
/// (dictionary_entries_fts) used by the importer and FTS test suites.
library;

import 'package:mekuru/core/database/database_provider.dart';

/// Passes iff the FTS index content exactly matches dictionary_entries.
/// The rank=1 argument makes FTS5 verify against the external-content
/// table, catching both missed and double-indexed rows — a plain
/// 'integrity-check' without it does not.
Future<void> expectGlossaryFtsConsistent(AppDatabase db) {
  return db.customStatement(
    "INSERT INTO dictionary_entries_fts(dictionary_entries_fts, rank) "
    "VALUES ('integrity-check', 1)",
  );
}

const glossaryFtsTriggers = {
  'dictionary_entries_fts_ai',
  'dictionary_entries_fts_ad',
  'dictionary_entries_fts_au',
};

Future<Set<Object?>> glossaryFtsTriggerNames(AppDatabase db) async {
  final rows = await db
      .customSelect("SELECT name FROM sqlite_master WHERE type = 'trigger'")
      .get();
  return rows.map((r) => r.data['name']).toSet();
}

/// Drops the three sync triggers (but not the FTS table), simulating a
/// database that lost them.
Future<void> dropGlossaryFtsTriggersForTest(AppDatabase db) async {
  for (final trigger in ['ai', 'ad', 'au']) {
    await db.customStatement('DROP TRIGGER dictionary_entries_fts_$trigger');
  }
}
