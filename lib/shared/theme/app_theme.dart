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
// shortcut: JIS X 0208 only (2.1 MB a weight); rarer kanji (剝, 𠮟) still come
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
/// [TextPainter]) must start from this style itself;
/// test/shared/japanese_text_locale_test.dart fails on a new one.
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

  /// Merged into the Material typography (as textTheme only: Material 3
  /// widgets don't read primaryTextTheme), so every theme-derived style (and
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

  /// [pureBlack]: black backgrounds for AMOLED screens. Raised surfaces stay
  /// near-black so cards, menus and dialogs keep an edge.
  static ThemeData darkTheme(Color seedColor, {bool pureBlack = false}) {
    var colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
    );
    if (pureBlack) {
      colorScheme = colorScheme.copyWith(
        surface: Colors.black,
        surfaceContainerLowest: const Color(0xFF0C0C0C),
        surfaceContainerLow: const Color(0xFF0C0C0C),
        surfaceContainer: const Color(0xFF0C0C0C),
        surfaceContainerHigh: const Color(0xFF131313),
        surfaceContainerHighest: const Color(0xFF1B1B1B),
      );
    }

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      textTheme: _japaneseTextTheme,
      scaffoldBackgroundColor: pureBlack
          ? Colors.black
          : const Color(0xFF121212),
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
        // Near-black in pure black, so a sheet's edge shows on a black screen.
        backgroundColor: pureBlack
            ? colorScheme.surfaceContainerLow
            : colorScheme.surface,
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

extension SuccessColor on ColorScheme {
  /// Green for success text and icons with 4.5:1 contrast on this scheme's
  /// surfaces. Plain [Colors.green] is about 2.7:1 on a light surface.
  Color get success => brightness == Brightness.dark
      ? Colors.green.shade300
      : Colors.green.shade800;
}
