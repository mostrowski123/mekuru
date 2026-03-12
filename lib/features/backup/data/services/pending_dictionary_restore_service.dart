import 'dart:convert';

import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/backup/data/models/backup_manifest.dart';
import 'package:mekuru/features/backup/data/models/pending_dictionary_restore.dart';
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

    final visibleDictionaries = await _getVisibleDictionaries(repository);
    final matchingNames = visibleDictionaries
        .where(
          (dictionary) => snapshot.preferences.any(
            (preference) => preference.name == dictionary.name,
          ),
        )
        .length;

    return PendingDictionaryRestorePreview(
      totalCount: snapshot.preferences.length,
      matchingCount: matchingNames,
      missingCount: snapshot.preferences.length - matchingNames,
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
    final preferenceByName = {
      for (final preference in snapshot.preferences)
        preference.name: preference,
    };
    final matched = visibleDictionaries
        .where((dictionary) => preferenceByName.containsKey(dictionary.name))
        .toList(growable: false);

    if (matched.isEmpty) {
      return ApplyPendingDictionaryRestoreResult(
        appliedCount: 0,
        missingCount: snapshot.preferences.length,
      );
    }

    final sortedMatched = [...matched]
      ..sort(
        (a, b) => preferenceByName[a.name]!.sortOrder.compareTo(
          preferenceByName[b.name]!.sortOrder,
        ),
      );
    final unmatched = visibleDictionaries
        .where((dictionary) => !preferenceByName.containsKey(dictionary.name))
        .toList(growable: false);

    await repository.reorderDictionaries([
      ...sortedMatched.map((dictionary) => dictionary.id),
      ...unmatched.map((dictionary) => dictionary.id),
    ]);

    for (final dictionary in sortedMatched) {
      final preference = preferenceByName[dictionary.name]!;
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
      missingCount: snapshot.preferences.length - sortedMatched.length,
    );
  }

  Future<List<DictionaryMeta>> _getVisibleDictionaries(
    DictionaryRepository repository,
  ) async {
    final dictionaries = await repository.getAllDictionaries();
    return dictionaries
        .where((dictionary) => !dictionary.isHidden)
        .toList(growable: false);
  }
}
