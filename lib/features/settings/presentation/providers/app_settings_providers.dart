import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/settings/data/services/ocr_server_config.dart'
    as ocr_server_config;
import 'package:mekuru/features/settings/data/services/app_settings_storage.dart';
import 'package:mekuru/shared/theme/app_theme.dart';

/// Provider for the app settings storage service.
final appSettingsStorageProvider = Provider<AppSettingsStorage>((ref) {
  return SharedPreferencesAppSettingsStorage();
});

/// Manages the app-wide theme mode.
class AppThemeNotifier extends Notifier<ThemeMode> {
  bool _hasLoadedPersistedSettings = false;

  @override
  ThemeMode build() => PreloadedAppSettings.initialThemeMode;

  /// Load persisted theme mode from storage (called once).
  Future<void> loadPersistedSettings() async {
    if (_hasLoadedPersistedSettings) return;
    _hasLoadedPersistedSettings = true;

    final persisted = await ref
        .read(appSettingsStorageProvider)
        .loadThemeMode();
    if (persisted != null) {
      state = persisted;
      PreloadedAppSettings.setThemeModeFromName(persisted.name);
    }
  }

  /// Set theme mode and persist to storage.
  void setThemeMode(ThemeMode mode) {
    state = mode;
    PreloadedAppSettings.setThemeModeFromName(mode.name);
    unawaited(ref.read(appSettingsStorageProvider).saveThemeMode(mode));
  }
}

/// Provider for the app theme mode.
final appThemeModeProvider = NotifierProvider<AppThemeNotifier, ThemeMode>(
  AppThemeNotifier.new,
);

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

    final persisted = await ref
        .read(appSettingsStorageProvider)
        .loadLookupFontSize();
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
final lookupFontSizeProvider = NotifierProvider<LookupFontSizeNotifier, double>(
  LookupFontSizeNotifier.new,
);

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

    final persisted = await ref
        .read(appSettingsStorageProvider)
        .loadSearchHistory();
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
      SearchHistoryNotifier.new,
    );

/// Manages the filter for hiding dictionary entries with Roman letters.
class FilterRomanLettersNotifier extends Notifier<bool> {
  bool _hasLoadedPersistedSettings = false;

  @override
  bool build() => false;

  /// Load persisted setting from storage (called once).
  Future<void> loadPersistedSettings() async {
    if (_hasLoadedPersistedSettings) return;
    _hasLoadedPersistedSettings = true;

    final persisted = await ref
        .read(appSettingsStorageProvider)
        .loadFilterRomanLetters();
    if (persisted != null) {
      state = persisted;
    }
  }

  /// Set the filter value and persist to storage.
  void setFilter(bool value) {
    state = value;
    unawaited(
      ref.read(appSettingsStorageProvider).saveFilterRomanLetters(value),
    );
  }
}

/// Provider for the Roman letter filter setting.
final filterRomanLettersProvider =
    NotifierProvider<FilterRomanLettersNotifier, bool>(
      FilterRomanLettersNotifier.new,
    );

/// Which screen the app opens to on cold start.
enum StartupScreen {
  library('Library'),
  dictionary('Dictionary'),
  lastRead('Last Read Book');

  final String label;
  const StartupScreen(this.label);
}

/// Manages the startup screen preference.
class StartupScreenNotifier extends Notifier<StartupScreen> {
  bool _hasLoadedPersistedSettings = false;
  bool _doneLoading = false;

  /// Whether the persisted value has been loaded from storage.
  bool get hasLoaded => _doneLoading;

  @override
  StartupScreen build() => StartupScreen.library;

  /// Load persisted startup screen from storage (called once).
  Future<void> loadPersistedSettings() async {
    if (_hasLoadedPersistedSettings) return;
    _hasLoadedPersistedSettings = true;

    final persisted = await ref
        .read(appSettingsStorageProvider)
        .loadStartupScreen();
    if (persisted != null) {
      state = StartupScreen.values.firstWhere(
        (e) => e.name == persisted,
        orElse: () => StartupScreen.library,
      );
    }
    _doneLoading = true;
  }

  /// Set the startup screen and persist to storage.
  void setStartupScreen(StartupScreen screen) {
    state = screen;
    unawaited(
      ref.read(appSettingsStorageProvider).saveStartupScreen(screen.name),
    );
  }
}

/// Provider for the startup screen setting.
final startupScreenProvider =
    NotifierProvider<StartupScreenNotifier, StartupScreen>(
      StartupScreenNotifier.new,
    );

/// Manages whether the dictionary search field auto-focuses on load.
class AutoFocusSearchNotifier extends Notifier<bool> {
  bool _hasLoadedPersistedSettings = false;

  @override
  bool build() => true;

  /// Load persisted setting from storage (called once).
  Future<void> loadPersistedSettings() async {
    if (_hasLoadedPersistedSettings) return;
    _hasLoadedPersistedSettings = true;

    final persisted = await ref
        .read(appSettingsStorageProvider)
        .loadAutoFocusSearch();
    if (persisted != null) {
      state = persisted;
    }
  }

  /// Set the value and persist to storage.
  void setAutoFocus(bool value) {
    state = value;
    unawaited(ref.read(appSettingsStorageProvider).saveAutoFocusSearch(value));
  }
}

/// Provider for the auto-focus search setting.
final autoFocusSearchProvider = NotifierProvider<AutoFocusSearchNotifier, bool>(
  AutoFocusSearchNotifier.new,
);

/// Manages the white threshold used for future manga auto-crop scans.
class AutoCropWhiteThresholdNotifier extends Notifier<int> {
  static const int defaultThreshold = 240;
  static const int minThreshold = 200;
  static const int maxThreshold = 255;

  bool _hasLoadedPersistedSettings = false;

  @override
  int build() => defaultThreshold;

  Future<void> loadPersistedSettings() async {
    if (_hasLoadedPersistedSettings) return;
    _hasLoadedPersistedSettings = true;

    final persisted = await ref
        .read(appSettingsStorageProvider)
        .loadAutoCropWhiteThreshold();
    if (persisted != null) {
      state = persisted.clamp(minThreshold, maxThreshold);
    }
  }

  void setThreshold(double value) {
    final next = value.round().clamp(minThreshold, maxThreshold);
    state = next;
    unawaited(
      ref.read(appSettingsStorageProvider).saveAutoCropWhiteThreshold(next),
    );
  }
}

final autoCropWhiteThresholdProvider =
    NotifierProvider<AutoCropWhiteThresholdNotifier, int>(
      AutoCropWhiteThresholdNotifier.new,
    );

/// Manages the app color theme selection.
class AppColorThemeNotifier extends Notifier<AppColorTheme> {
  bool _hasLoadedPersistedSettings = false;

  @override
  AppColorTheme build() {
    final name = PreloadedAppSettings.initialColorThemeName;
    if (name == null) return AppColorTheme.mekuruRed;
    return AppColorTheme.values.firstWhere(
      (e) => e.name == name,
      orElse: () => AppColorTheme.mekuruRed,
    );
  }

  /// Load persisted color theme from storage (called once).
  Future<void> loadPersistedSettings() async {
    if (_hasLoadedPersistedSettings) return;
    _hasLoadedPersistedSettings = true;

    final persisted = await ref
        .read(appSettingsStorageProvider)
        .loadColorTheme();
    if (persisted != null) {
      final restoredTheme = AppColorTheme.values.firstWhere(
        (e) => e.name == persisted,
        orElse: () => AppColorTheme.mekuruRed,
      );
      state = restoredTheme;
      PreloadedAppSettings.setColorThemeName(restoredTheme.name);
    }
  }

  /// Set color theme and persist to storage.
  void setColorTheme(AppColorTheme theme) {
    state = theme;
    PreloadedAppSettings.setColorThemeName(theme.name);
    unawaited(ref.read(appSettingsStorageProvider).saveColorTheme(theme.name));
  }
}

/// Provider for the app color theme.
final appColorThemeProvider =
    NotifierProvider<AppColorThemeNotifier, AppColorTheme>(
      AppColorThemeNotifier.new,
    );

/// Manages the OCR server URL.
class OcrServerUrlNotifier extends Notifier<String> {
  static const defaultUrl = ocr_server_config.defaultOcrServerUrl;
  bool _hasLoadedPersistedSettings = false;

  @override
  String build() => defaultUrl;

  Future<void> loadPersistedSettings() async {
    if (_hasLoadedPersistedSettings) return;
    _hasLoadedPersistedSettings = true;

    final persisted = await ref
        .read(appSettingsStorageProvider)
        .loadOcrServerUrl();
    if (persisted != null && persisted.isNotEmpty) {
      state = persisted;
    }
  }

  void setUrl(String url) {
    state = url;
    unawaited(ref.read(appSettingsStorageProvider).saveOcrServerUrl(url));
  }
}

String normalizeOcrServerUrl(String url) {
  return ocr_server_config.normalizeOcrServerUrl(url);
}

bool isBuiltInOcrServerUrl(String url) {
  return ocr_server_config.isUnsetOrBuiltInOcrServerUrl(url);
}

/// Provider for the OCR server URL.
final ocrServerUrlProvider = NotifierProvider<OcrServerUrlNotifier, String>(
  OcrServerUrlNotifier.new,
);
