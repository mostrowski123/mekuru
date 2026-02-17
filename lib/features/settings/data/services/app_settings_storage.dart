import 'dart:convert';

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
  Future<List<String>> loadSearchHistory();
  Future<void> saveSearchHistory(List<String> history);
  Future<bool?> loadFilterRomanLetters();
  Future<void> saveFilterRomanLetters(bool value);
  Future<String?> loadAnkidroidConfig();
  Future<void> saveAnkidroidConfig(String configJson);
}

/// SharedPreferences-backed implementation of [AppSettingsStorage].
class SharedPreferencesAppSettingsStorage implements AppSettingsStorage {
  static const _themeModeKey = 'app.theme_mode';
  static const _sortOrderKey = 'app.library_sort_order';
  static const _lookupFontSizeKey = 'app.lookup_font_size';
  static const _searchHistoryKey = 'app.dictionary_search_history';
  static const _filterRomanLettersKey = 'app.filter_roman_letters';
  static const _ankidroidConfigKey = 'app.ankidroid_config';

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

  @override
  Future<List<String>> loadSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_searchHistoryKey);
    if (value == null) return [];
    try {
      final decoded = jsonDecode(value);
      return (decoded as List<dynamic>).cast<String>();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> saveSearchHistory(List<String> history) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_searchHistoryKey, jsonEncode(history));
  }

  @override
  Future<bool?> loadFilterRomanLetters() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_filterRomanLettersKey);
  }

  @override
  Future<void> saveFilterRomanLetters(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_filterRomanLettersKey, value);
  }

  @override
  Future<String?> loadAnkidroidConfig() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_ankidroidConfigKey);
  }

  @override
  Future<void> saveAnkidroidConfig(String configJson) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ankidroidConfigKey, configJson);
  }
}
