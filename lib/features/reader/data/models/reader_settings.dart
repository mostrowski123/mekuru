enum ReaderDirection { ltr, rtl }

ReaderDirection readerDirectionFromString(String? value) {
  return switch (value) {
    'ltr' => ReaderDirection.ltr,
    'rtl' => ReaderDirection.rtl,
    _ => ReaderDirection.rtl,
  };
}

extension ReaderDirectionStorage on ReaderDirection {
  String get storageValue => name;
}

enum ColorMode { normal, sepia, dark }

ColorMode colorModeFromString(String? value) {
  return switch (value) {
    'sepia' => ColorMode.sepia,
    'dark' => ColorMode.dark,
    _ => ColorMode.normal,
  };
}

extension ColorModeStorage on ColorMode {
  String get storageValue => name;
}

/// Reader display and interaction preferences.
class ReaderSettings {
  final double fontSize;
  final bool verticalText;
  final ReaderDirection readingDirection;
  final bool pageTurnAnimationEnabled;
  final int horizontalPadding;
  final int verticalPadding;

  /// Swipe sensitivity as a fraction of screen dimension (0.01–0.20).
  /// Lower values require less finger movement to trigger a swipe.
  final double swipeSensitivity;

  final ColorMode colorMode;
  final bool keepScreenOn;

  /// Sepia warmth level (0.0 = almost white, 1.0 = full sepia). Only used
  /// when [colorMode] is [ColorMode.sepia].
  final double sepiaIntensity;

  /// When true, hyperlinks in the EPUB are disabled — tapping linked text
  /// triggers a dictionary lookup instead of navigating. Links are always
  /// styled blue regardless of this setting.
  final bool disableLinks;

  const ReaderSettings({
    this.fontSize = 18,
    this.verticalText = true,
    this.readingDirection = ReaderDirection.rtl,
    this.pageTurnAnimationEnabled = true,
    this.horizontalPadding = 28,
    this.verticalPadding = 28,
    this.swipeSensitivity = 0.05,
    this.colorMode = ColorMode.normal,
    this.keepScreenOn = false,
    this.sepiaIntensity = 0.5,
    this.disableLinks = false,
  });

  ReaderSettings copyWith({
    double? fontSize,
    bool? verticalText,
    ReaderDirection? readingDirection,
    bool? pageTurnAnimationEnabled,
    int? horizontalPadding,
    int? verticalPadding,
    double? swipeSensitivity,
    ColorMode? colorMode,
    bool? keepScreenOn,
    double? sepiaIntensity,
    bool? disableLinks,
  }) {
    return ReaderSettings(
      fontSize: fontSize ?? this.fontSize,
      verticalText: verticalText ?? this.verticalText,
      readingDirection: readingDirection ?? this.readingDirection,
      pageTurnAnimationEnabled:
          pageTurnAnimationEnabled ?? this.pageTurnAnimationEnabled,
      horizontalPadding: horizontalPadding ?? this.horizontalPadding,
      verticalPadding: verticalPadding ?? this.verticalPadding,
      swipeSensitivity: swipeSensitivity ?? this.swipeSensitivity,
      colorMode: colorMode ?? this.colorMode,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      sepiaIntensity: sepiaIntensity ?? this.sepiaIntensity,
      disableLinks: disableLinks ?? this.disableLinks,
    );
  }
}
