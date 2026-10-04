import 'dart:convert';

import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/backup/data/models/backup_manifest.dart';
import 'package:mekuru/features/backup/data/models/pending_dictionary_restore.dart';
import 'package:mekuru/features/dictionary/data/models/dictionary_catalog.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PendingDictionaryRestoreService {
  static const pendingRestoreKey = 'backup.pending_dictionary_restore';

  Future<RestoreDictionaryPreferencesResult> queueFromBackup({
    required List<BackupDictionaryPreference> preferences,
    required bool shouldQueue,
    required DictionaryRepository repository,
  }) async {
    if (!shouldQueue || preferences.isEmpty) {
      await clearPendingRestore();
      return RestoreDictionaryPreferencesResult(
        skipped: !shouldQueue && preferences.isNotEmpty,
        totalCount: preferences.length,
      );
    }

    await savePendingRestore(preferences);
    final preview = await getPendingRestorePreview(repository);
    return RestoreDictionaryPreferencesResult(
      queued: true,
      totalCount: preferences.length,
      matchingCount: preview?.matchingCount ?? 0,
      missingCount: preview?.missingCount ?? preferences.length,
    );
  }

  Future<void> savePendingRestore(
    List<BackupDictionaryPreference> preferences,
  ) async {
    if (preferences.isEmpty) {
      await clearPendingRestore();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final sortedPreferences = [...preferences]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final snapshot = PendingDictionaryRestoreSnapshot(
      preferences: sortedPreferences,
    );
    await prefs.setString(pendingRestoreKey, jsonEncode(snapshot.toJson()));
  }

  Future<PendingDictionaryRestoreSnapshot?> loadPendingRestore() async {
    final prefs = await SharedPreferences.getInstance();
    final rawJson = prefs.getString(pendingRestoreKey);
    if (rawJson == null || rawJson.isEmpty) return null;

    try {
      final parsed = jsonDecode(rawJson);
      if (parsed is! Map<String, dynamic>) {
        await clearPendingRestore();
        return null;
      }

      final snapshot = PendingDictionaryRestoreSnapshot.fromJson(parsed);
      if (snapshot.preferences.isEmpty) {
        await clearPendingRestore();
        return null;
      }
      return snapshot;
    } catch (_) {
      await clearPendingRestore();
      return null;
    }
  }

  Future<void> clearPendingRestore() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(pendingRestoreKey);
  }

  Future<PendingDictionaryRestorePreview?> getPendingRestorePreview(
    DictionaryRepository repository,
  ) async {
    final snapshot = await loadPendingRestore();
    if (snapshot == null) return null;

    final matches = _preferenceById(
      snapshot.preferences,
      await _getVisibleDictionaries(repository),
    );
    return PendingDictionaryRestorePreview(
      totalCount: snapshot.preferences.length,
      matchingCount: matches.length,
      missingCount: _missingCount(snapshot.preferences, matches),
    );
  }

  Future<ApplyPendingDictionaryRestoreResult> applyPendingRestore(
    DictionaryRepository repository,
  ) async {
    final snapshot = await loadPendingRestore();
    if (snapshot == null) {
      return const ApplyPendingDictionaryRestoreResult(
        appliedCount: 0,
        missingCount: 0,
      );
    }

    final visibleDictionaries = await _getVisibleDictionaries(repository);
    final matches = _preferenceById(snapshot.preferences, visibleDictionaries);
    if (matches.isEmpty) {
      return ApplyPendingDictionaryRestoreResult(
        appliedCount: 0,
        missingCount: snapshot.preferences.length,
      );
    }

    final sortedMatched =
        [
          for (final dictionary in visibleDictionaries)
            if (matches.containsKey(dictionary.id)) dictionary,
        ]..sort(
          (a, b) =>
              matches[a.id]!.sortOrder.compareTo(matches[b.id]!.sortOrder),
        );
    await repository.reorderDictionaries([
      ...sortedMatched.map((dictionary) => dictionary.id),
      for (final dictionary in visibleDictionaries)
        if (!matches.containsKey(dictionary.id)) dictionary.id,
    ]);

    for (final dictionary in sortedMatched) {
      final preference = matches[dictionary.id]!;
      if (dictionary.isEnabled != preference.isEnabled) {
        await repository.toggleDictionary(
          dictionary.id,
          isEnabled: preference.isEnabled,
        );
      }
    }

    await clearPendingRestore();
    return ApplyPendingDictionaryRestoreResult(
      appliedCount: sortedMatched.length,
      missingCount: _missingCount(snapshot.preferences, matches),
    );
  }

  /// The backed-up preference for each installed dictionary: the one with
  /// its exact title, else one with its display name, so a preference
  /// still applies after an update changed the date in a title.
  static Map<int, BackupDictionaryPreference> _preferenceById(
    List<BackupDictionaryPreference> preferences,
    List<DictionaryMeta> dictionaries,
  ) {
    final byTitle = {for (final p in preferences) p.name: p};
    final byName = {
      for (final p in preferences) dictionaryDisplayName(p.name): p,
    };
    return {
      for (final dictionary in dictionaries)
        dictionary.id:
            ?(byTitle[dictionary.name] ??
            byName[dictionaryDisplayName(dictionary.name)]),
    };
  }

  /// Preferences no installed dictionary took.
  static int _missingCount(
    List<BackupDictionaryPreference> preferences,
    Map<int, BackupDictionaryPreference> matches,
  ) => preferences.length - matches.values.toSet().length;

  Future<List<DictionaryMeta>> _getVisibleDictionaries(
    DictionaryRepository repository,
  ) async {
    final dictionaries = await repository.getAllDictionaries();
    return dictionaries
        .where((dictionary) => !dictionary.isHidden)
        .toList(growable: false);
  }
}
