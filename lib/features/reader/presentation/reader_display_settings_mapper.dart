import 'package:flutter/material.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';

/// Theme data for the custom EPUB viewer.
class ReaderTheme {
  final Color foregroundColor;
  final Color backgroundColor;
  final Map<String, dynamic>? customCss;

  const ReaderTheme({
    required this.foregroundColor,
    required this.backgroundColor,
    this.customCss,
  });
}

ReaderTheme buildReaderTheme({
  required ReaderSettings settings,
}) {
  // Note: margins are handled separately via setMargins() in reader_bridge.js
  // by applying padding to the .epub-container div. epub.js Stage.size()
  // automatically subtracts container padding from layout dimensions.

  final Color bgColor;
  final Color fgColor;

  switch (settings.colorMode) {
    case ColorMode.sepia:
      const sepiaBg = Color(0xFFF5E6C8);
      const sepiaFg = Color(0xFF5B4636);
      bgColor = Color.lerp(Colors.white, sepiaBg, settings.sepiaIntensity)!;
      fgColor = Color.lerp(Colors.black, sepiaFg, settings.sepiaIntensity)!;
    case ColorMode.dark:
      bgColor = const Color(0xFF1A1A1A);
      fgColor = const Color(0xFFE0E0E0);
    case ColorMode.normal:
      bgColor = Colors.white;
      fgColor = Colors.black;
  }

  String colorToHex(Color c) {
    final r = (c.r * 255.0).round().clamp(0, 255);
    final g = (c.g * 255.0).round().clamp(0, 255);
    final b = (c.b * 255.0).round().clamp(0, 255);
    return '#${r.toRadixString(16).padLeft(2, '0').toUpperCase()}'
        '${g.toRadixString(16).padLeft(2, '0').toUpperCase()}'
        '${b.toRadixString(16).padLeft(2, '0').toUpperCase()}';
  }

  final bgHex = colorToHex(bgColor);
  final fgHex = colorToHex(fgColor);

  final Map<String, dynamic> htmlCss = {
    'background': '$bgHex !important',
    'color': '$fgHex !important',
  };
  final Map<String, dynamic> bodyCss = {
    'background': '$bgHex !important',
    'color': '$fgHex !important',
  };

  // Force horizontal writing mode when vertical text is disabled.
  // This overrides EPUB CSS that may specify writing-mode: vertical-rl.
  // We also need to reset direction and text-align because Japanese EPUBs
  // typically set these for RTL vertical layout, which causes right-justified
  // text when the writing mode is forced to horizontal.
  if (!settings.verticalText) {
    htmlCss['writing-mode'] = 'horizontal-tb !important';
    bodyCss['writing-mode'] = 'horizontal-tb !important';
    htmlCss['direction'] = 'ltr !important';
    bodyCss['direction'] = 'ltr !important';
    bodyCss['text-align'] = 'start !important';
  }

  return ReaderTheme(
    foregroundColor: fgColor,
    backgroundColor: bgColor,
    customCss: {
      'html': htmlCss,
      'body': bodyCss,
      'p': {
        'color': '$fgHex !important',
      },
      'span': {
        'color': '$fgHex !important',
      },
      'a': {
        'color': '$fgHex !important',
      },
    },
  );
}
