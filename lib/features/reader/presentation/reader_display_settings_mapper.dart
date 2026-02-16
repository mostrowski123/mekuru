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

  return ReaderTheme(
    foregroundColor: fgColor,
    backgroundColor: bgColor,
    customCss: {
      'html': {
        'background': '$bgHex !important',
        'color': '$fgHex !important',
      },
      'body': {
        'background': '$bgHex !important',
        'color': '$fgHex !important',
      },
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
