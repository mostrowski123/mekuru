import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class ReaderSettingsStorage {
  Future<ReaderSettings?> load();

  Future<void> save(ReaderSettings settings);
}

class SharedPreferencesReaderSettingsStorage implements ReaderSettingsStorage {
  static const _fontSizeKey = 'reader.font_size';
  static const _pageTurnAnimationKey = 'reader.page_turn_animation';
  static const _horizontalPaddingKey = 'reader.horizontal_padding';
  static const _verticalPaddingKey = 'reader.vertical_padding';
  static const _swipeSensitivityKey = 'reader.swipe_sensitivity';
  static const _colorModeKey = 'reader.color_mode';
  static const _keepScreenOnKey = 'reader.keep_screen_on';
  static const _sepiaIntensityKey = 'reader.sepia_intensity';

  @override
  Future<ReaderSettings?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSavedSettings =
        prefs.containsKey(_fontSizeKey) ||
        prefs.containsKey(_pageTurnAnimationKey) ||
        prefs.containsKey(_horizontalPaddingKey) ||
        prefs.containsKey(_verticalPaddingKey) ||
        prefs.containsKey(_swipeSensitivityKey) ||
        prefs.containsKey(_colorModeKey) ||
        prefs.containsKey(_keepScreenOnKey) ||
        prefs.containsKey(_sepiaIntensityKey);

    if (!hasSavedSettings) {
      return null;
    }

    return ReaderSettings(
      fontSize: prefs.getDouble(_fontSizeKey) ?? 18,
      // verticalText and readingDirection are per-book settings stored in the
      // Books table — not loaded from global preferences. Use class defaults.
      pageTurnAnimationEnabled: prefs.getBool(_pageTurnAnimationKey) ?? true,
      horizontalPadding: prefs.getInt(_horizontalPaddingKey) ?? 28,
      verticalPadding: prefs.getInt(_verticalPaddingKey) ?? 28,
      swipeSensitivity: prefs.getDouble(_swipeSensitivityKey) ?? 0.05,
      colorMode: colorModeFromString(prefs.getString(_colorModeKey)),
      keepScreenOn: prefs.getBool(_keepScreenOnKey) ?? false,
      sepiaIntensity: prefs.getDouble(_sepiaIntensityKey) ?? 0.5,
    );
  }

  @override
  Future<void> save(ReaderSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontSizeKey, settings.fontSize);
    // verticalText and readingDirection are per-book — not saved globally.
    await prefs.setBool(
      _pageTurnAnimationKey,
      settings.pageTurnAnimationEnabled,
    );
    await prefs.setInt(_horizontalPaddingKey, settings.horizontalPadding);
    await prefs.setInt(_verticalPaddingKey, settings.verticalPadding);
    await prefs.setDouble(_swipeSensitivityKey, settings.swipeSensitivity);
    await prefs.setString(_colorModeKey, settings.colorMode.storageValue);
    await prefs.setBool(_keepScreenOnKey, settings.keepScreenOn);
    await prefs.setDouble(_sepiaIntensityKey, settings.sepiaIntensity);
  }
}
