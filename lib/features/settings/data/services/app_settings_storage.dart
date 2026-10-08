import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mekuru/features/settings/data/services/enhanced_furigana_dict_download_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguage {
  system('system'),
  english('en'),
  spanish('es'),
  indonesian('id'),
  simplifiedChinese('zh_Hans');

  const AppLanguage(this.storageValue);

  final String storageValue;

  static AppLanguage fromStorageValue(String? value) {
    for (final language in values) {
      if (language.storageValue == value) {
        return language;
      }
    }
    return AppLanguage.system;
  }
}

Locale? appLanguageLocaleOverride(AppLanguage language) {
  return switch (language) {
    AppLanguage.system => null,
    AppLanguage.english => const Locale('en'),
    AppLanguage.spanish => const Locale('es'),
    AppLanguage.indonesian => const Locale('id'),
    AppLanguage.simplifiedChinese => const Locale.fromSubtags(
      languageCode: 'zh',
      scriptCode: 'Hans',
    ),
  };
}

Locale resolveSupportedAppLocale(
  Locale? preferredLocale,
  Iterable<Locale> supportedLocales,
) {
  final supported = supportedLocales.toList(growable: false);
  if (supported.isEmpty) {
    return const Locale('en');
  }

  final englishFallback = _fallbackEnglishLocale(supported);
  if (preferredLocale == null) {
    return englishFallback;
  }

  for (final locale in supported) {
    if (_sameLocale(locale, preferredLocale)) {
      return locale;
    }
  }

  if (preferredLocale.languageCode == 'zh') {
    return _resolveSupportedChineseLocale(preferredLocale, supported) ??
        englishFallback;
  }

  for (final locale in supported) {
    if (locale.languageCode == preferredLocale.languageCode &&
        (locale.scriptCode == null || locale.scriptCode!.isEmpty) &&
        (locale.countryCode == null || locale.countryCode!.isEmpty)) {
      return locale;
    }
  }

  return englishFallback;
}

Locale _fallbackEnglishLocale(List<Locale> supportedLocales) {
  for (final locale in supportedLocales) {
    if (locale.languageCode == 'en') {
      return locale;
    }
  }
  return supportedLocales.first;
}

Locale? _resolveSupportedChineseLocale(
  Locale preferredLocale,
  List<Locale> supportedLocales,
) {
  Locale? baseChineseLocale;
  Locale? simplifiedChineseLocale;

  for (final locale in supportedLocales) {
    if (locale.languageCode != 'zh') continue;
    if (locale.scriptCode == 'Hans') {
      simplifiedChineseLocale = locale;
    } else if ((locale.scriptCode == null || locale.scriptCode!.isEmpty) &&
        (locale.countryCode == null || locale.countryCode!.isEmpty)) {
      baseChineseLocale = locale;
    }
  }

  if (preferredLocale.scriptCode == 'Hans') {
    return simplifiedChineseLocale ?? baseChineseLocale;
  }
  if (preferredLocale.scriptCode == 'Hant') {
    return null;
  }

  switch (preferredLocale.countryCode) {
    case 'CN':
    case 'SG':
      return simplifiedChineseLocale ?? baseChineseLocale;
    case 'TW':
    case 'HK':
    case 'MO':
      return null;
  }

  if ((preferredLocale.scriptCode == null ||
          preferredLocale.scriptCode!.isEmpty) &&
      (preferredLocale.countryCode == null ||
          preferredLocale.countryCode!.isEmpty)) {
    return baseChineseLocale ?? simplifiedChineseLocale;
  }

  return null;
}

bool _sameLocale(Locale a, Locale b) {
  return a.languageCode == b.languageCode &&
      (a.scriptCode ?? '') == (b.scriptCode ?? '') &&
      (a.countryCode ?? '') == (b.countryCode ?? '');
}

/// Abstract interface for app-level settings persistence.
abstract class AppSettingsStorage {
  Future<AppLanguage?> loadAppLanguage();
  Future<void> saveAppLanguage(AppLanguage language);
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
  Future<String?> loadStartupScreen();
  Future<void> saveStartupScreen(String screen);
  Future<String?> loadSentenceTranslationMode();
  Future<void> saveSentenceTranslationMode(String mode);
  Future<String?> loadTranslationModel();
  Future<void> saveTranslationModel(String model);
  Future<bool?> loadAutoFocusSearch();
  Future<void> saveAutoFocusSearch(bool value);
  Future<bool?> loadLowRamMode();
  Future<void> saveLowRamMode(bool value);
  Future<bool?> loadLowRamHintNever();
  Future<void> saveLowRamHintNever(bool value);
  Future<DateTime?> loadLowRamHintLastShown();
  Future<void> saveLowRamHintLastShown(DateTime value);
  Future<String?> loadColorTheme();
  Future<void> saveColorTheme(String theme);
  Future<int?> loadAutoCropWhiteThreshold();
  Future<void> saveAutoCropWhiteThreshold(int value);
  Future<String?> loadOcrServerUrl();
  Future<void> saveOcrServerUrl(String url);
  Future<bool?> loadOcrServerAllowSelfSigned();
  Future<void> saveOcrServerAllowSelfSigned(bool value);
  Future<bool?> loadEnhancedFuriganaDictEnabled();
  Future<void> saveEnhancedFuriganaDictEnabled(bool enabled);
}

/// Holds theme values and Low RAM mode pre-loaded in [main] so Riverpod
/// notifiers can use them as initial state on the very first frame (no
/// async gap).
class PreloadedAppSettings {
  static AppLanguage initialAppLanguage = AppLanguage.system;
  static ThemeMode initialThemeMode = ThemeMode.dark;
  static String? initialColorThemeName;
  static bool initialLowRamMode = false;

  static void setAppLanguageFromValue(String? language) {
    initialAppLanguage = AppLanguage.fromStorageValue(language);
  }

  static void setThemeModeFromName(String? themeStr) {
    initialThemeMode = switch (themeStr) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
  }

  static void setColorThemeName(String? name) {
    initialColorThemeName = name;
  }

  /// Call once in [main] before [runApp].
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    setAppLanguageFromValue(prefs.getString('app.language'));
    setThemeModeFromName(prefs.getString('app.theme_mode'));
    setColorThemeName(prefs.getString('app.color_theme'));
    initialLowRamMode =
        prefs.getBool(SharedPreferencesAppSettingsStorage.lowRamModeKey) ??
        false;
  }
}

/// SharedPreferences-backed implementation of [AppSettingsStorage].
class SharedPreferencesAppSettingsStorage implements AppSettingsStorage {
  static const _appLanguageKey = 'app.language';
  static const _themeModeKey = 'app.theme_mode';
  static const _sortOrderKey = 'app.library_sort_order';
  static const _lookupFontSizeKey = 'app.lookup_font_size';
  static const _searchHistoryKey = 'app.dictionary_search_history';
  static const _filterRomanLettersKey = 'app.filter_roman_letters';
  static const _ankidroidConfigKey = 'app.ankidroid_config';
  static const _startupScreenKey = 'app.startup_screen';
  static const _sentenceTranslationModeKey = 'app.sentence_translation_mode';
  static const _translationModelKey = 'app.translation_model';
  static const _autoFocusSearchKey = 'app.auto_focus_search';

  /// Low RAM mode and its offer belong to the device, not to the library:
  /// left out of [allKeys], and kept by a full restore.
  static const lowRamModeKey = 'app.low_ram_mode';
  static const lowRamHintNeverKey = 'app.low_ram_hint_never';
  static const lowRamHintLastShownKey = 'app.low_ram_hint_last_shown';

  static const _colorThemeKey = 'app.color_theme';
  static const _autoCropWhiteThresholdKey = 'app.auto_crop_white_threshold';
  static const _ocrServerUrlKey = 'app.ocr_server_url';
  static const _ocrServerAllowSelfSignedKey =
      'app.ocr_server_allow_self_signed';

  /// Every SharedPreferences key this storage reads or writes, but the
  /// device's own (Low RAM mode). The backup service derives its app key
  /// list from this, so a key added here is automatically included in
  /// backups.
  static const List<String> allKeys = [
    _appLanguageKey,
    _themeModeKey,
    _sortOrderKey,
    _lookupFontSizeKey,
    _searchHistoryKey,
    _filterRomanLettersKey,
    _ankidroidConfigKey,
    _startupScreenKey,
    _sentenceTranslationModeKey,
    _translationModelKey,
    _autoFocusSearchKey,
    _colorThemeKey,
    _autoCropWhiteThresholdKey,
    _ocrServerUrlKey,
    _ocrServerAllowSelfSignedKey,
    EnhancedFuriganaDictDownloadService.enabledPreferenceKey,
  ];

  @override
  Future<AppLanguage?> loadAppLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_appLanguageKey);
    if (value == null) return null;
    return AppLanguage.fromStorageValue(value);
  }

  @override
  Future<void> saveAppLanguage(AppLanguage language) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_appLanguageKey, language.storageValue);
  }

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

  @override
  Future<String?> loadStartupScreen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_startupScreenKey);
  }

  @override
  Future<void> saveStartupScreen(String screen) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_startupScreenKey, screen);
  }

  @override
  Future<String?> loadSentenceTranslationMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_sentenceTranslationModeKey);
  }

  @override
  Future<void> saveSentenceTranslationMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sentenceTranslationModeKey, mode);
  }

  @override
  Future<String?> loadTranslationModel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_translationModelKey);
  }

  @override
  Future<void> saveTranslationModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_translationModelKey, model);
  }

  @override
  Future<bool?> loadAutoFocusSearch() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoFocusSearchKey);
  }

  @override
  Future<void> saveAutoFocusSearch(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoFocusSearchKey, value);
  }

  @override
  Future<bool?> loadLowRamMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(lowRamModeKey);
  }

  @override
  Future<void> saveLowRamMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(lowRamModeKey, value);
  }

  @override
  Future<bool?> loadLowRamHintNever() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(lowRamHintNeverKey);
  }

  @override
  Future<void> saveLowRamHintNever(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(lowRamHintNeverKey, value);
  }

  @override
  Future<DateTime?> loadLowRamHintLastShown() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(lowRamHintLastShownKey);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  @override
  Future<void> saveLowRamHintLastShown(DateTime value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(lowRamHintLastShownKey, value.millisecondsSinceEpoch);
  }

  @override
  Future<String?> loadColorTheme() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_colorThemeKey);
  }

  @override
  Future<void> saveColorTheme(String theme) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_colorThemeKey, theme);
  }

  @override
  Future<int?> loadAutoCropWhiteThreshold() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_autoCropWhiteThresholdKey);
  }

  @override
  Future<void> saveAutoCropWhiteThreshold(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_autoCropWhiteThresholdKey, value);
  }

  @override
  Future<String?> loadOcrServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_ocrServerUrlKey);
  }

  @override
  Future<void> saveOcrServerUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ocrServerUrlKey, url);
  }

  @override
  Future<bool?> loadOcrServerAllowSelfSigned() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_ocrServerAllowSelfSignedKey);
  }

  @override
  Future<void> saveOcrServerAllowSelfSigned(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_ocrServerAllowSelfSignedKey, value);
  }

  @override
  Future<bool?> loadEnhancedFuriganaDictEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(
      EnhancedFuriganaDictDownloadService.enabledPreferenceKey,
    );
  }

  @override
  Future<void> saveEnhancedFuriganaDictEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      EnhancedFuriganaDictDownloadService.enabledPreferenceKey,
      enabled,
    );
  }
}
