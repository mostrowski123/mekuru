// Pure Dart — no Flutter imports, so this stays unit-testable.
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';

final _whitespace = RegExp(r'\s+');

/// Approximate readable-character count of a manga page: the whitespace-
/// stripped length of all OCR text blocks.
///
/// Mokuro OCR text carries no ruby markup, so [MokuroTextBlock.fullText] is
/// already base text. That keeps this count consistent with the EPUB counter,
/// which deliberately excludes furigana ruby so a page's count does not change
/// when furigana are toggled on or off.
int charCountForPage(MokuroPage page) => page.blocks.fold(
  0,
  (sum, block) => sum + block.fullText.replaceAll(_whitespace, '').length,
);
