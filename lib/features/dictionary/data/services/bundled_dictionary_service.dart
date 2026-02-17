import 'dart:io';

import 'package:flutter/services.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_importer.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Service for auto-importing bundled dictionaries on first launch.
class BundledDictionaryService {
  static const _jpdbFreqAsset =
      'assets/jpdb_freq/JPDB_v2.2_Frequency_Kana_2024-10-13.zip';
  static const _jpdbFreqPrefKey = 'bundled_jpdb_freq_imported';

  /// Import the bundled JPDB frequency dictionary if not already imported.
  ///
  /// Checks SharedPreferences first (fast), then falls back to a DB name check.
  /// After import, disables the dictionary for search (it has no definitions).
  static Future<void> importBundledFrequencyDictionary(
    DictionaryRepository repository,
    DictionaryImporter importer,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Fast path: already imported
      if (prefs.getBool(_jpdbFreqPrefKey) == true) return;

      // Check if dictionary already exists in DB (handles upgrade from
      // pre-flag version or re-install with existing DB)
      final existing = await repository.getDictionaryByName('JPDBv2\u32D5');
      if (existing != null) {
        await prefs.setBool(_jpdbFreqPrefKey, true);
        return;
      }

      // Load ZIP from asset bundle and write to a temp file
      final data = await rootBundle.load(_jpdbFreqAsset);
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(p.join(tempDir.path, 'jpdb_freq_bundled.zip'));
      await tempFile.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );

      try {
        // Import the dictionary
        await importer.importFromFile(tempFile.path);

        // Disable the frequency dictionary for search results — it has no
        // term definitions, only frequency metadata used for ranking.
        final imported =
            await repository.getDictionaryByName('JPDBv2\u32D5');
        if (imported != null) {
          await repository.toggleDictionary(imported.id, isEnabled: false);
        }

        // Mark as imported
        await prefs.setBool(_jpdbFreqPrefKey, true);
      } finally {
        // Clean up temp file
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      }
    } catch (_) {
      // Non-fatal: app still works without frequency data.
      // Will retry on next launch since the pref flag wasn't set.
    }
  }
}
