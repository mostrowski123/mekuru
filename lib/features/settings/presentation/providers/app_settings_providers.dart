import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/settings/data/services/app_settings_storage.dart';

/// Provider for the app settings storage service.
final appSettingsStorageProvider = Provider<AppSettingsStorage>((ref) {
  return SharedPreferencesAppSettingsStorage();
});

/// Manages the app-wide theme mode.
class AppThemeNotifier extends Notifier<ThemeMode> {
  bool _hasLoadedPersistedSettings = false;

  @override
  ThemeMode build() => ThemeMode.dark;

  /// Load persisted theme mode from storage (called once).
  Future<void> loadPersistedSettings() async {
    if (_hasLoadedPersistedSettings) return;
    _hasLoadedPersistedSettings = true;

    final persisted = await ref.read(appSettingsStorageProvider).loadThemeMode();
    if (persisted != null) {
      state = persisted;
    }
  }

  /// Set theme mode and persist to storage.
  void setThemeMode(ThemeMode mode) {
    state = mode;
    unawaited(ref.read(appSettingsStorageProvider).saveThemeMode(mode));
  }
}

/// Provider for the app theme mode.
final appThemeModeProvider =
    NotifierProvider<AppThemeNotifier, ThemeMode>(AppThemeNotifier.new);

/// Manages the lookup bottom sheet font size.
class LookupFontSizeNotifier extends Notifier<double> {
  static const double defaultSize = 16.0;
  static const double minSize = 12.0;
  static const double maxSize = 24.0;

  bool _hasLoadedPersistedSettings = false;

  @override
  double build() => defaultSize;

  /// Load persisted font size from storage (called once).
  Future<void> loadPersistedSettings() async {
    if (_hasLoadedPersistedSettings) return;
    _hasLoadedPersistedSettings = true;

    final persisted =
        await ref.read(appSettingsStorageProvider).loadLookupFontSize();
    if (persisted != null) {
      state = persisted.clamp(minSize, maxSize);
    }
  }

  /// Set font size and persist to storage.
  void setFontSize(double size) {
    state = size.clamp(minSize, maxSize);
    unawaited(ref.read(appSettingsStorageProvider).saveLookupFontSize(state));
  }
}

/// Provider for the lookup font size.
final lookupFontSizeProvider =
    NotifierProvider<LookupFontSizeNotifier, double>(
        LookupFontSizeNotifier.new);

/// Manages the dictionary search history.
class SearchHistoryNotifier extends Notifier<List<String>> {
  static const int maxEntries = 20;
  bool _hasLoadedPersistedSettings = false;

  @override
  List<String> build() => [];

  /// Load persisted search history from storage (called once).
  Future<void> loadPersistedSettings() async {
    if (_hasLoadedPersistedSettings) return;
    _hasLoadedPersistedSettings = true;

    final persisted =
        await ref.read(appSettingsStorageProvider).loadSearchHistory();
    if (persisted.isNotEmpty) {
      state = persisted;
    }
  }

  /// Add a search term to history (most recent first, deduplicated).
  void addSearch(String term) {
    final trimmed = term.trim();
    if (trimmed.isEmpty) return;

    final updated = [trimmed, ...state.where((s) => s != trimmed)];
    if (updated.length > maxEntries) {
      state = updated.sublist(0, maxEntries);
    } else {
      state = updated;
    }
    unawaited(ref.read(appSettingsStorageProvider).saveSearchHistory(state));
  }

  /// Remove a single search term from history.
  void removeSearch(String term) {
    state = state.where((s) => s != term).toList();
    unawaited(ref.read(appSettingsStorageProvider).saveSearchHistory(state));
  }

  /// Clear all search history.
  void clearAll() {
    state = [];
    unawaited(ref.read(appSettingsStorageProvider).saveSearchHistory(state));
  }
}

/// Provider for the dictionary search history.
final searchHistoryProvider =
    NotifierProvider<SearchHistoryNotifier, List<String>>(
        SearchHistoryNotifier.new);

/// Manages the filter for hiding dictionary entries with Roman letters.
class FilterRomanLettersNotifier extends Notifier<bool> {
  bool _hasLoadedPersistedSettings = false;

  @override
  bool build() => false;

  /// Load persisted setting from storage (called once).
  Future<void> loadPersistedSettings() async {
    if (_hasLoadedPersistedSettings) return;
    _hasLoadedPersistedSettings = true;

    final persisted =
        await ref.read(appSettingsStorageProvider).loadFilterRomanLetters();
    if (persisted != null) {
      state = persisted;
    }
  }

  /// Set the filter value and persist to storage.
  void setFilter(bool value) {
    state = value;
    unawaited(
        ref.read(appSettingsStorageProvider).saveFilterRomanLetters(value));
  }
}

/// Provider for the Roman letter filter setting.
final filterRomanLettersProvider =
    NotifierProvider<FilterRomanLettersNotifier, bool>(
        FilterRomanLettersNotifier.new);
