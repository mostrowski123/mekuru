import 'package:drift/drift.dart';

/// Counts rows in [table], optionally filtered, without loading them.
Future<int> countRows(
  GeneratedDatabase db,
  TableInfo<Table, dynamic> table, {
  Expression<bool>? where,
}) async {
  final count = countAll();
  final query = db.selectOnly(table)..addColumns([count]);
  if (where != null) {
    query.where(where);
  }
  final row = await query.getSingle();
  return row.read(count) ?? 0;
}
