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

enum FuriganaMode { off, all, aboveLevel }

FuriganaMode furiganaModeFromString(String? value) {
  return switch (value) {
    'all' => FuriganaMode.all,
    'aboveLevel' => FuriganaMode.aboveLevel,
    _ => FuriganaMode.off,
  };
}

extension FuriganaModeStorage on FuriganaMode {
  String get storageValue => name;
}

/// Default width fraction reserved for page-turn taps on each device edge in
/// the manga reader.
const double kDefaultMangaPageTurnEdgeZoneWidthFraction = 0.15;

/// Minimum width fraction reserved for page-turn taps on each device edge in
/// the manga reader.
const double kMinMangaPageTurnEdgeZoneWidthFraction = 0.05;

/// Maximum width fraction reserved for page-turn taps on each device edge in
/// the manga reader.
const double kMaxMangaPageTurnEdgeZoneWidthFraction = 0.25;

double clampMangaPageTurnEdgeZoneWidthFraction(double value) {
  return value
      .clamp(
        kMinMangaPageTurnEdgeZoneWidthFraction,
        kMaxMangaPageTurnEdgeZoneWidthFraction,
      )
      .toDouble();
}

double mangaCenterTapZoneWidthFromEdgeZoneWidth(double edgeZoneWidthFraction) {
  final clampedEdgeZoneWidth = clampMangaPageTurnEdgeZoneWidthFraction(
    edgeZoneWidthFraction,
  );
  return 1.0 - (clampedEdgeZoneWidth * 2);
}

/// Reader display and interaction preferences.
class ReaderSettings {
  final double fontSize;
  final bool verticalText;

  /// When true, vertical text is laid out in two stacked blocks per page
  /// (top and bottom rows, like newspaper 段組) instead of full-height lines.
  /// Only takes effect while [verticalText] is enabled.
  final bool splitVerticalText;

  final ReaderDirection readingDirection;
  final bool pageTurnAnimationEnabled;
  final int horizontalPadding;
  final int verticalPadding;

  /// Swipe sensitivity as a fraction of screen dimension (0.01–0.20).
  /// Lower values require less finger movement to trigger a swipe.
  final double swipeSensitivity;

  /// Width fraction reserved for page-turn taps on each device edge in the
  /// manga reader.
  final double mangaPageTurnEdgeZoneWidthFraction;

  final ColorMode colorMode;
  final bool keepScreenOn;

  /// Sepia warmth level (0.0 = almost white, 1.0 = full sepia). Only used
  /// when [colorMode] is [ColorMode.sepia].
  final double sepiaIntensity;

  /// When true, hyperlinks in the EPUB are disabled — tapping linked text
  /// triggers a dictionary lookup instead of navigating. Links are always
  /// styled blue regardless of this setting.
  final bool disableLinks;

  /// Controls whether and how furigana is rendered above kanji in the reader.
  ///
  /// - [FuriganaMode.off]: hide all furigana, including EPUB-authored ruby.
  /// - [FuriganaMode.all]: show EPUB-authored ruby and generate ruby (via
  ///   MeCab) for kanji that lack it.
  /// - [FuriganaMode.aboveLevel]: reserved for a future difficulty-aware
  ///   filter. Currently behaves like [FuriganaMode.all].
  final FuriganaMode furiganaMode;

  const ReaderSettings({
    this.fontSize = 18,
    this.verticalText = true,
    this.splitVerticalText = false,
    this.readingDirection = ReaderDirection.rtl,
    this.pageTurnAnimationEnabled = true,
    this.horizontalPadding = 28,
    this.verticalPadding = 28,
    this.swipeSensitivity = 0.05,
    this.mangaPageTurnEdgeZoneWidthFraction =
        kDefaultMangaPageTurnEdgeZoneWidthFraction,
    this.colorMode = ColorMode.normal,
    this.keepScreenOn = false,
    this.sepiaIntensity = 0.5,
    this.disableLinks = false,
    this.furiganaMode = FuriganaMode.off,
  });

  ReaderSettings copyWith({
    double? fontSize,
    bool? verticalText,
    bool? splitVerticalText,
    ReaderDirection? readingDirection,
    bool? pageTurnAnimationEnabled,
    int? horizontalPadding,
    int? verticalPadding,
    double? swipeSensitivity,
    double? mangaPageTurnEdgeZoneWidthFraction,
    ColorMode? colorMode,
    bool? keepScreenOn,
    double? sepiaIntensity,
    bool? disableLinks,
    FuriganaMode? furiganaMode,
  }) {
    return ReaderSettings(
      fontSize: fontSize ?? this.fontSize,
      verticalText: verticalText ?? this.verticalText,
      splitVerticalText: splitVerticalText ?? this.splitVerticalText,
      readingDirection: readingDirection ?? this.readingDirection,
      pageTurnAnimationEnabled:
          pageTurnAnimationEnabled ?? this.pageTurnAnimationEnabled,
      horizontalPadding: horizontalPadding ?? this.horizontalPadding,
      verticalPadding: verticalPadding ?? this.verticalPadding,
      swipeSensitivity: swipeSensitivity ?? this.swipeSensitivity,
      mangaPageTurnEdgeZoneWidthFraction:
          mangaPageTurnEdgeZoneWidthFraction ??
          this.mangaPageTurnEdgeZoneWidthFraction,
      colorMode: colorMode ?? this.colorMode,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      sepiaIntensity: sepiaIntensity ?? this.sepiaIntensity,
      disableLinks: disableLinks ?? this.disableLinks,
      furiganaMode: furiganaMode ?? this.furiganaMode,
    );
  }
}
