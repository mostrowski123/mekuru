import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Abstract interface for app-level settings persistence.
abstract class AppSettingsStorage {
  Future<ThemeMode?> loadThemeMode();
  Future<void> saveThemeMode(ThemeMode mode);
  Future<String?> loadSortOrder();
  Future<void> saveSortOrder(String order);
  Future<double?> loadLookupFontSize();
  Future<void> saveLookupFontSize(double size);
}

/// SharedPreferences-backed implementation of [AppSettingsStorage].
class SharedPreferencesAppSettingsStorage implements AppSettingsStorage {
  static const _themeModeKey = 'app.theme_mode';
  static const _sortOrderKey = 'app.library_sort_order';
  static const _lookupFontSizeKey = 'app.lookup_font_size';

  @override
  Future<ThemeMode?> loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_themeModeKey);
    if (value == null) return null;
    return switch (value) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
  }

  @override
  Future<void> saveThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, mode.name);
  }

  @override
  Future<String?> loadSortOrder() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_sortOrderKey);
  }

  @override
  Future<void> saveSortOrder(String order) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sortOrderKey, order);
  }

  @override
  Future<double?> loadLookupFontSize() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_lookupFontSizeKey);
  }

  @override
  Future<void> saveLookupFontSize(double size) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_lookupFontSizeKey, size);
  }
}
