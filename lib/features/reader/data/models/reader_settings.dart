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

enum FuriganaMode { hide, book, all, aboveLevel }

FuriganaMode furiganaModeFromString(String? value) {
  return switch (value) {
    'hide' => FuriganaMode.hide,
    'all' => FuriganaMode.all,
    'aboveLevel' => FuriganaMode.aboveLevel,
    // Deliberately no 'off' case: versions <= 1.25.x persisted 'off' (both
    // the global preference and per-book Books.furigana_mode overrides) as a
    // hide-everything default most users never chose. Letting 'off' fall
    // through to `book` retroactively converts those installs with no
    // migration. Do not add an 'off' case.
    _ => FuriganaMode.book,
  };
}

extension FuriganaModeStorage on FuriganaMode {
  String get storageValue => name;
}

/// Manga page layout modes.
enum MangaViewMode { singlePage, twoPageSpread, scroll }

MangaViewMode mangaViewModeFromString(String? value) {
  return switch (value) {
    'twoPageSpread' => MangaViewMode.twoPageSpread,
    'scroll' => MangaViewMode.scroll,
    _ => MangaViewMode.singlePage,
  };
}

extension MangaViewModeStorage on MangaViewMode {
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
  /// - [FuriganaMode.hide]: hide all furigana, including EPUB-authored ruby.
  /// - [FuriganaMode.book]: show EPUB-authored ruby only; never generate.
  /// - [FuriganaMode.all]: show EPUB-authored ruby and generate ruby (via
  ///   MeCab) for kanji that lack it.
  /// - [FuriganaMode.aboveLevel]: like [FuriganaMode.all], but only words
  ///   containing at least one kanji harder than [furiganaJlptLevel] are
  ///   annotated.
  final FuriganaMode furiganaMode;

  /// JLPT threshold for [FuriganaMode.aboveLevel]: 5 (N5) … 1 (N1). Words
  /// whose kanji are all at or below this level render without generated
  /// furigana. Global — not per book.
  final int furiganaJlptLevel;

  /// Screen brightness override (0.0–1.0) applied while a reader is open.
  /// `null` means follow the system brightness.
  final double? brightness;

  /// Manga: page layout mode (single page, two-page spread, or scroll).
  final MangaViewMode mangaViewMode;

  /// Manga: reading direction for page turns and spread ordering.
  final ReaderDirection mangaReadingDirection;

  /// Manga: whether pages are cropped to their detected content bounds
  /// (Pro feature).
  final bool mangaAutoCrop;

  /// Manga: whether the lookup sheet uses a transparent background.
  final bool mangaTransparentLookup;

  /// Manga: whether programmatic page turns animate. Disable for e-reader
  /// (e-ink) displays, where transitions ghost.
  final bool mangaPageTurnAnimation;

  const ReaderSettings({
    this.fontSize = 18,
    this.verticalText = true,
    this.splitVerticalText = false,
    this.readingDirection = ReaderDirection.rtl,
    this.horizontalPadding = 28,
    this.verticalPadding = 28,
    this.swipeSensitivity = 0.05,
    this.mangaPageTurnEdgeZoneWidthFraction =
        kDefaultMangaPageTurnEdgeZoneWidthFraction,
    this.colorMode = ColorMode.normal,
    this.keepScreenOn = false,
    this.sepiaIntensity = 0.5,
    this.disableLinks = false,
    this.furiganaMode = FuriganaMode.book,
    this.furiganaJlptLevel = 3,
    this.brightness,
    this.mangaViewMode = MangaViewMode.singlePage,
    this.mangaReadingDirection = ReaderDirection.rtl,
    this.mangaAutoCrop = false,
    this.mangaTransparentLookup = true,
    this.mangaPageTurnAnimation = true,
  });

  ReaderSettings copyWith({
    double? fontSize,
    bool? verticalText,
    bool? splitVerticalText,
    ReaderDirection? readingDirection,
    int? horizontalPadding,
    int? verticalPadding,
    double? swipeSensitivity,
    double? mangaPageTurnEdgeZoneWidthFraction,
    ColorMode? colorMode,
    bool? keepScreenOn,
    double? sepiaIntensity,
    bool? disableLinks,
    FuriganaMode? furiganaMode,
    int? furiganaJlptLevel,
    double? brightness,
    bool clearBrightness = false,
    MangaViewMode? mangaViewMode,
    ReaderDirection? mangaReadingDirection,
    bool? mangaAutoCrop,
    bool? mangaTransparentLookup,
    bool? mangaPageTurnAnimation,
  }) {
    return ReaderSettings(
      fontSize: fontSize ?? this.fontSize,
      verticalText: verticalText ?? this.verticalText,
      splitVerticalText: splitVerticalText ?? this.splitVerticalText,
      readingDirection: readingDirection ?? this.readingDirection,
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
      furiganaJlptLevel: furiganaJlptLevel ?? this.furiganaJlptLevel,
      brightness: clearBrightness ? null : (brightness ?? this.brightness),
      mangaViewMode: mangaViewMode ?? this.mangaViewMode,
      mangaReadingDirection:
          mangaReadingDirection ?? this.mangaReadingDirection,
      mangaAutoCrop: mangaAutoCrop ?? this.mangaAutoCrop,
      mangaTransparentLookup:
          mangaTransparentLookup ?? this.mangaTransparentLookup,
      mangaPageTurnAnimation:
          mangaPageTurnAnimation ?? this.mangaPageTurnAnimation,
    );
  }
}
