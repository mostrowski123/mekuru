import 'package:drift/drift.dart';

abstract final class DictionaryEntryKinds {
  static const regular = 'regular';
  static const kanji = 'kanji';
}

/// DictionaryEntries table — individual term entries from Yomitan dictionaries.
///
/// Yomitan term_bank schema:
///   [expression, reading, definition_tags, rules, score, glossary, sequence, term_tags]
///
/// We index `expression` and `reading` for fast lookups.
/// `glossaries` is stored as JSON-encoded text (`List<String>`).
@TableIndex(name: 'idx_expression', columns: {#expression})
@TableIndex(name: 'idx_reading', columns: {#reading})
@TableIndex(name: 'idx_expr_dictid', columns: {#expression, #dictionaryId})
@TableIndex(name: 'idx_read_dictid', columns: {#reading, #dictionaryId})
class DictionaryEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get expression => text()();
  TextColumn get reading => text().withDefault(const Constant(''))();
  TextColumn get entryKind =>
      text().withDefault(const Constant(DictionaryEntryKinds.regular))();
  TextColumn get kanjiOnyomi => text().withDefault(const Constant(''))();
  TextColumn get kanjiKunyomi => text().withDefault(const Constant(''))();
  TextColumn get definitionTags => text().withDefault(const Constant(''))();
  TextColumn get rules => text().withDefault(const Constant(''))();
  TextColumn get termTags => text().withDefault(const Constant(''))();
  TextColumn get glossaries => text()(); // JSON-encoded List<String>
  IntColumn get dictionaryId => integer()();
}
