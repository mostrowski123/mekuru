import 'package:drift/native.dart';
import 'package:mekuru/core/database/database_provider.dart';

/// In-memory database for unit tests. Always `await db.close()` in tearDown.
AppDatabase createTestDatabase() => AppDatabase(NativeDatabase.memory());
