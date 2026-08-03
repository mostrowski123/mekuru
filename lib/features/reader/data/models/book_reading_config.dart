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
bool bookIsNaturallyRtl({String? language, String? pageProgressionDirection}) {
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
/// Uses the `primary-writing-mode` OPF metadata when available to determine
/// whether the book uses vertical text. This is independent of
/// `page-progression-direction` — an RTL page progression does not
/// necessarily mean vertical text.
///
/// When that metadata is absent, [hasVerticalCss] — whether any of the
/// EPUB's stylesheets declare a vertical `writing-mode` (sniffed at import)
/// — decides instead: true forces vertical, false defaults to horizontal
/// unless the spine explicitly declares `page-progression-direction="rtl"`.
/// True vertical books (Aozora-style) always declare vertical-rl in CSS, so
/// this keeps their vertical default while fixing horizontally-authored
/// EPUBs (e.g. Calibre conversions) that used to open forced-vertical.
///
/// `null` [hasVerticalCss] means the book was imported before CSS sniffing
/// existed; the legacy heuristic (vertical when naturally RTL) applies.
bool defaultVerticalText({
  String? language,
  String? pageProgressionDirection,
  String? primaryWritingMode,
  bool? hasVerticalCss,
}) {
  if (!bookSupportsVerticalText(language)) return false;

  // Explicit writing-mode metadata takes priority.
  if (primaryWritingMode != null) {
    return primaryWritingMode.contains('vertical');
  }

  // Sniffed stylesheets decide next; when none declare vertical writing,
  // only an explicit rtl spine keeps the vertical default.
  if (hasVerticalCss != null) {
    return hasVerticalCss || pageProgressionDirection == 'rtl';
  }

  // Sniff result unknown: use the old heuristic.
  return bookIsNaturallyRtl(
    language: language,
    pageProgressionDirection: pageProgressionDirection,
  );
}
