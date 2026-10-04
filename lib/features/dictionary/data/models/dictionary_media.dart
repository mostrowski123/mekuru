import 'package:drift/drift.dart';

/// DictionaryMedia table — image files from a Yomitan dictionary zip,
/// referenced by `img` nodes and image glossary items through [path].
///
/// Stored in the database rather than as files so full backups carry them
/// and no absolute path needs re-anchoring when the iOS container moves.
@DataClassName('DictionaryMediaFile')
class DictionaryMedia extends Table {
  IntColumn get dictionaryId => integer()();

  /// Path inside the zip, with `\` normalized to `/` by the repository.
  TextColumn get path => text()();
  BlobColumn get bytes => blob()();

  @override
  Set<Column> get primaryKey => {dictionaryId, path};
}
