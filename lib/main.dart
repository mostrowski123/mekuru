import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/database/database_provider.dart';
import 'features/dictionary/data/repositories/dictionary_repository.dart';
import 'features/dictionary/data/services/bundled_dictionary_service.dart';
import 'features/dictionary/data/services/dictionary_importer.dart';
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

  // Import bundled frequency dictionary on first launch.
  // Uses a temporary DB instance — the Riverpod-managed one is created later.
  final db = AppDatabase();
  final repo = DictionaryRepository(db);
  final importer = DictionaryImporter(repo);
  await BundledDictionaryService.importBundledFrequencyDictionary(
    repo,
    importer,
  );
  await db.close();

  runApp(const ProviderScope(child: MekuruApp()));
}
