import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:mekuru/core/database/database_provider.dart';

/// In-memory database for unit tests. Always `await db.close()` in tearDown.
/// [intercept] sees every query, for a test that counts them (`SelectLog`).
AppDatabase createTestDatabase({QueryInterceptor? intercept}) {
  final memory = NativeDatabase.memory();
  return AppDatabase(
    intercept == null ? memory : memory.interceptWith(intercept),
  );
}
