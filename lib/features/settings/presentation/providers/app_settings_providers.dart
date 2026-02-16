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
