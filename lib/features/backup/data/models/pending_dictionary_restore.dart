import 'backup_manifest.dart';

class PendingDictionaryRestoreSnapshot {
  final List<BackupDictionaryPreference> preferences;

  const PendingDictionaryRestoreSnapshot({required this.preferences});

  factory PendingDictionaryRestoreSnapshot.fromJson(Map<String, dynamic> json) {
    final rawPreferences = json['preferences'];
    final preferences = rawPreferences is List
        ? rawPreferences
              .whereType<Map>()
              .map((item) => _decodePreference(Map<String, dynamic>.from(item)))
              .toList(growable: false)
        : const <BackupDictionaryPreference>[];
    return PendingDictionaryRestoreSnapshot(preferences: preferences);
  }

  Map<String, dynamic> toJson() => {
    'preferences': preferences.map(_encodePreference).toList(growable: false),
  };
}

class PendingDictionaryRestorePreview {
  final int totalCount;
  final int matchingCount;
  final int missingCount;

  const PendingDictionaryRestorePreview({
    required this.totalCount,
    required this.matchingCount,
    required this.missingCount,
  });

  bool get canApply => matchingCount > 0;
}

class ApplyPendingDictionaryRestoreResult {
  final int appliedCount;
  final int missingCount;

  const ApplyPendingDictionaryRestoreResult({
    required this.appliedCount,
    required this.missingCount,
  });
}

class RestoreDictionaryPreferencesResult {
  final bool queued;
  final bool skipped;
  final int totalCount;
  final int matchingCount;
  final int missingCount;

  const RestoreDictionaryPreferencesResult({
    this.queued = false,
    this.skipped = false,
    this.totalCount = 0,
    this.matchingCount = 0,
    this.missingCount = 0,
  });

  bool get hasPreferences => totalCount > 0;
}

Map<String, dynamic> _encodePreference(BackupDictionaryPreference preference) {
  return {
    'name': preference.name,
    'sortOrder': preference.sortOrder,
    'isEnabled': preference.isEnabled,
  };
}

BackupDictionaryPreference _decodePreference(Map<String, dynamic> json) {
  return BackupDictionaryPreference(
    name: json['name'] as String? ?? '',
    sortOrder: json['sortOrder'] as int? ?? 0,
    isEnabled: json['isEnabled'] as bool? ?? true,
  );
}
