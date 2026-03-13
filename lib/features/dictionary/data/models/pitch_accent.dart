import 'package:drift/drift.dart';

/// PitchAccents table — pitch accent data from Yomitan dictionaries.
///
/// Stores the downstep position for each expression/reading pair.
/// Position 0 = heiban (flat), position 1 = atamadaka, etc.
@TableIndex(name: 'idx_pitch_expression', columns: {#expression})
@TableIndex(name: 'idx_pitch_reading', columns: {#reading})
@TableIndex(
  name: 'idx_pitch_expr_dictid',
  columns: {#expression, #dictionaryId},
)
class PitchAccents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get expression => text()();
  TextColumn get reading => text().withDefault(const Constant(''))();
  IntColumn get downstepPosition => integer()();
  IntColumn get dictionaryId => integer()();
}
