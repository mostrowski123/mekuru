import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/database/database_provider.dart';
import 'features/reader/data/services/mecab_service.dart';

/// Global Riverpod provider for the Drift database instance.
/// Created once at app startup and disposed when the app is torn down.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await MecabService.instance.init();

  runApp(const ProviderScope(child: MekuruApp()));
}
