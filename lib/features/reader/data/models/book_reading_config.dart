import 'package:mekuru/features/reader/data/models/reader_settings.dart';

/// Whether a book supports vertical text display.
///
/// Only CJK languages (Japanese, Chinese, Korean) support vertical text.
/// English and other LTR-language books should never be displayed vertically.
/// Returns `true` for `null` language (legacy books assumed Japanese).
bool bookSupportsVerticalText(String? language) {
  if (language == null) return true;
  final lang = language.toLowerCase();
  return lang == 'ja' || lang == 'zh' || lang == 'ko';
}

/// Whether a book's natural reading direction is RTL.
///
/// Uses the explicit `page-progression-direction` from the EPUB spine first,
/// then falls back to language-based defaults (Japanese → RTL, others → LTR).
/// Returns `true` for `null` language (legacy books assumed Japanese).
bool bookIsNaturallyRtl({
  String? language,
  String? pageProgressionDirection,
}) {
  if (pageProgressionDirection == 'rtl') return true;
  if (pageProgressionDirection == 'ltr') return false;

  if (language == null) return true;
  return language.toLowerCase() == 'ja';
}

/// Returns the default [ReaderDirection] for a book when first opened.
ReaderDirection defaultReaderDirection({
  String? language,
  String? pageProgressionDirection,
}) {
  return bookIsNaturallyRtl(
    language: language,
    pageProgressionDirection: pageProgressionDirection,
  )
      ? ReaderDirection.rtl
      : ReaderDirection.ltr;
}

/// Returns the default vertical text setting for a book when first opened.
///
/// Vertical text is only the default when the book's language supports it
/// AND the book is naturally RTL (e.g., Japanese vertical reading).
bool defaultVerticalText({
  String? language,
  String? pageProgressionDirection,
}) {
  return bookSupportsVerticalText(language) &&
      bookIsNaturallyRtl(
        language: language,
        pageProgressionDirection: pageProgressionDirection,
      );
}
