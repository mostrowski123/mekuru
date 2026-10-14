import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/shared/theme/app_theme.dart';

void main() {
  const seed = Color(0xFFB71C1C);

  test('pure black makes the dark theme background black', () {
    final theme = AppTheme.darkTheme(seed, pureBlack: true);

    expect(theme.scaffoldBackgroundColor, Colors.black);
    expect(theme.colorScheme.surface, Colors.black);
    expect(theme.appBarTheme.backgroundColor, Colors.black);
  });

  test('the dark theme stays gray without pure black', () {
    final theme = AppTheme.darkTheme(seed);

    expect(theme.scaffoldBackgroundColor, const Color(0xFF121212));
    expect(
      theme.colorScheme.surface,
      ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.dark,
      ).surface,
    );
  });
}
