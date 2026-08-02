import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class ReaderSettingsStorage {
  Future<ReaderSettings?> load();

  Future<void> save(ReaderSettings settings);
}

class SharedPreferencesReaderSettingsStorage implements ReaderSettingsStorage {
  static const _fontSizeKey = 'reader.font_size';
  static const _horizontalPaddingKey = 'reader.horizontal_padding';
  static const _verticalPaddingKey = 'reader.vertical_padding';
  static const _swipeSensitivityKey = 'reader.swipe_sensitivity';
  static const _mangaPageTurnEdgeZoneWidthKey =
      'reader.manga_page_turn_edge_zone_width';
  static const _colorModeKey = 'reader.color_mode';
  static const _keepScreenOnKey = 'reader.keep_screen_on';
  static const _sepiaIntensityKey = 'reader.sepia_intensity';
  static const _disableLinksKey = 'reader.disable_links';
  static const _furiganaModeKey = 'reader.furigana_mode';
  static const _splitVerticalTextKey = 'reader.split_vertical_text';
  static const _brightnessKey = 'reader.brightness';

  /// Every SharedPreferences key this storage reads or writes. The backup
  /// service derives its reader key list from this, so a key added here is
  /// automatically included in backups.
  static const List<String> allKeys = [
    _fontSizeKey,
    _horizontalPaddingKey,
    _verticalPaddingKey,
    _swipeSensitivityKey,
    _mangaPageTurnEdgeZoneWidthKey,
    _colorModeKey,
    _keepScreenOnKey,
    _sepiaIntensityKey,
    _disableLinksKey,
    _furiganaModeKey,
    _splitVerticalTextKey,
    _brightnessKey,
  ];

  @override
  Future<ReaderSettings?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSavedSettings = allKeys.any(prefs.containsKey);

    if (!hasSavedSettings) {
      return null;
    }

    return ReaderSettings(
      fontSize: prefs.getDouble(_fontSizeKey) ?? 18,
      // verticalText and readingDirection are per-book settings stored in the
      // Books table — not loaded from global preferences. Use class defaults.
      horizontalPadding: prefs.getInt(_horizontalPaddingKey) ?? 28,
      verticalPadding: prefs.getInt(_verticalPaddingKey) ?? 28,
      swipeSensitivity: prefs.getDouble(_swipeSensitivityKey) ?? 0.05,
      mangaPageTurnEdgeZoneWidthFraction:
          clampMangaPageTurnEdgeZoneWidthFraction(
            prefs.getDouble(_mangaPageTurnEdgeZoneWidthKey) ??
                kDefaultMangaPageTurnEdgeZoneWidthFraction,
          ),
      colorMode: colorModeFromString(prefs.getString(_colorModeKey)),
      keepScreenOn: prefs.getBool(_keepScreenOnKey) ?? false,
      sepiaIntensity: prefs.getDouble(_sepiaIntensityKey) ?? 0.5,
      disableLinks: prefs.getBool(_disableLinksKey) ?? false,
      furiganaMode: furiganaModeFromString(prefs.getString(_furiganaModeKey)),
      splitVerticalText: prefs.getBool(_splitVerticalTextKey) ?? false,
      brightness: prefs.getDouble(_brightnessKey),
    );
  }

  @override
  Future<void> save(ReaderSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontSizeKey, settings.fontSize);
    // verticalText and readingDirection are per-book — not saved globally.
    await prefs.setInt(_horizontalPaddingKey, settings.horizontalPadding);
    await prefs.setInt(_verticalPaddingKey, settings.verticalPadding);
    await prefs.setDouble(_swipeSensitivityKey, settings.swipeSensitivity);
    await prefs.setDouble(
      _mangaPageTurnEdgeZoneWidthKey,
      settings.mangaPageTurnEdgeZoneWidthFraction,
    );
    await prefs.setString(_colorModeKey, settings.colorMode.storageValue);
    await prefs.setBool(_keepScreenOnKey, settings.keepScreenOn);
    await prefs.setDouble(_sepiaIntensityKey, settings.sepiaIntensity);
    await prefs.setBool(_disableLinksKey, settings.disableLinks);
    await prefs.setString(_furiganaModeKey, settings.furiganaMode.storageValue);
    await prefs.setBool(_splitVerticalTextKey, settings.splitVerticalText);
    // An absent key means "follow the system brightness".
    final brightness = settings.brightness;
    if (brightness == null) {
      await prefs.remove(_brightnessKey);
    } else {
      await prefs.setDouble(_brightnessKey, brightness);
    }
  }
}
