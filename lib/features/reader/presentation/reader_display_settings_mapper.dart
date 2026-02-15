import 'package:flutter/material.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';

/// Theme data for the custom EPUB viewer.
class ReaderTheme {
  final Color foregroundColor;
  final Map<String, dynamic>? customCss;

  const ReaderTheme({
    required this.foregroundColor,
    this.customCss,
  });
}

ReaderTheme buildReaderTheme({
  required ReaderSettings settings,
}) {
  // Note: margins are handled separately via setMargins() in reader_bridge.js
  // by applying padding to the .epub-container div. epub.js Stage.size()
  // automatically subtracts container padding from layout dimensions.
  return ReaderTheme(
    foregroundColor: Colors.black,
    customCss: {
      'html': {
        'background': '#FFFFFF !important',
        'color': '#000000 !important',
      },
      'body': {
        'background': '#FFFFFF !important',
        'color': '#000000 !important',
      },
      'p': {
        'color': '#000000 !important',
      },
      'span': {
        'color': '#000000 !important',
      },
      'a': {
        'color': '#000000 !important',
      },
    },
  );
}
