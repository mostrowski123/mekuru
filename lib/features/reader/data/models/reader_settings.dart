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

  const ReaderSettings({
    this.fontSize = 18,
    this.verticalText = true,
    this.readingDirection = ReaderDirection.rtl,
    this.pageTurnAnimationEnabled = true,
    this.horizontalPadding = 28,
    this.verticalPadding = 28,
    this.swipeSensitivity = 0.05,
  });

  ReaderSettings copyWith({
    double? fontSize,
    bool? verticalText,
    ReaderDirection? readingDirection,
    bool? pageTurnAnimationEnabled,
    int? horizontalPadding,
    int? verticalPadding,
    double? swipeSensitivity,
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
    );
  }
}
