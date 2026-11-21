import 'package:drift/drift.dart';

/// Records every query a database is asked to read. Wrap a test database's
/// executor with it: `AppDatabase(NativeDatabase.memory().interceptWith(log))`.
class SelectLog extends QueryInterceptor {
  final statements = <String>[];

  /// The recorded queries that read any of [tables].
  List<String> reading(List<String> tables) => [
    for (final statement in statements)
      if (tables.any(statement.contains)) statement,
  ];

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    statements.add(statement);
    return super.runSelect(executor, statement, args);
  }
}
