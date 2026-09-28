import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Locale for any text that may contain Japanese.
///
/// Chinese and Japanese share code points for Han characters but draw some
/// of them differently (直 is one). Font fallback picks the face from the
/// text's locale, which defaults to the UI language, so an English UI gets
/// the Chinese glyphs on both Android and iOS.
const Locale japaneseTextLocale = Locale('ja', 'JP');

/// Bundled Japanese font: kana, CJK punctuation and the JIS X 0208 kanji of
/// Noto Sans JP, without Latin.
// ponytail: JIS X 0208 only (2.1 MB a weight); rarer kanji (剝, 𠮟) still come
// from the system font. Widen the range in tools/subset_japanese_font.py if
// they show up in Chinese forms.
const String japaneseFontFamily = 'NotoSansJP';

/// Base style for any text that may contain Japanese.
///
/// The locale is enough where the system font has no kanji (stock Android,
/// iOS): fallback then picks the Japanese face. Xiaomi, OnePlus and Oppo
/// phones ship a system font that has every kanji in its Chinese form, so
/// fallback never runs and the locale is ignored. On Android the bundled
/// font therefore comes first; the rest falls through to what an unset
/// family resolved to before (Roboto where it exists by name, else the
/// system default). Text that bypasses the theme (a bare [RichText] or
/// [TextPainter]) must start from this style itself.
TextStyle get japaneseTextStyle =>
    defaultTargetPlatform == TargetPlatform.android
    ? const TextStyle(
        locale: japaneseTextLocale,
        fontFamily: japaneseFontFamily,
        fontFamilyFallback: ['Roboto', 'sans-serif'],
      )
    : const TextStyle(locale: japaneseTextLocale);

/// Available color themes for the app.
enum AppColorTheme {
  // Default — the app's signature Japanese-inspired red
  mekuruRed(Color(0xFFB71C1C)),
  indigo(Color(0xFF3F51B5)),
  teal(Color(0xFF009688)),
  deepPurple(Color(0xFF673AB7)),
  blue(Color(0xFF2196F3)),
  green(Color(0xFF4CAF50)),
  orange(Color(0xFFFF9800)),
  pink(Color(0xFFE91E63)),
  blueGrey(Color(0xFF607D8B));

  final Color seedColor;

  const AppColorTheme(this.seedColor);
}

/// App-wide theme configuration using Material 3 color schemes.
class AppTheme {
  AppTheme._();

  /// Merged into the Material typography, so every theme-derived style (and
  /// every [Text] under a [Material], through [DefaultTextStyle]) renders
  /// Han characters with Japanese glyphs whatever the UI language.
  static TextTheme get _japaneseTextTheme {
    final japanese = japaneseTextStyle;
    return TextTheme(
      displayLarge: japanese,
      displayMedium: japanese,
      displaySmall: japanese,
      headlineLarge: japanese,
      headlineMedium: japanese,
      headlineSmall: japanese,
      titleLarge: japanese,
      titleMedium: japanese,
      titleSmall: japanese,
      bodyLarge: japanese,
      bodyMedium: japanese,
      bodySmall: japanese,
      labelLarge: japanese,
      labelMedium: japanese,
      labelSmall: japanese,
    );
  }

  static ThemeData darkTheme(Color seedColor) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      textTheme: _japaneseTextTheme,
      primaryTextTheme: _japaneseTextTheme,
      scaffoldBackgroundColor: const Color(0xFF121212),
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: colorScheme.surfaceContainerHighest,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  static ThemeData lightTheme(Color seedColor) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      textTheme: _japaneseTextTheme,
      primaryTextTheme: _japaneseTextTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
