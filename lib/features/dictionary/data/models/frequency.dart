import 'package:drift/drift.dart';

/// Frequencies table — word frequency rank data from Yomitan dictionaries.
///
/// Stores the frequency rank for each expression/reading pair.
/// Lower rank = more common word (rank 1 is the most frequent).
@TableIndex(name: 'idx_freq_expression', columns: {#expression})
@TableIndex(name: 'idx_freq_reading', columns: {#reading})
@TableIndex(name: 'idx_freq_expr_read', columns: {#expression, #reading})
class Frequencies extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get expression => text()();
  TextColumn get reading => text().withDefault(const Constant(''))();
  IntColumn get frequencyRank => integer()();
  IntColumn get dictionaryId => integer()();
}
