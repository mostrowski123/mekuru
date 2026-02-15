import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/presentation/reader_display_settings_mapper.dart';

void main() {
  group('buildReaderTheme', () {
    test('forces high contrast light theme', () {
      final theme = buildReaderTheme(settings: const ReaderSettings());

      expect(theme.foregroundColor, Colors.black);
      expect(theme.customCss, isNotNull);
    });

    test('body CSS includes color but not padding (margins handled separately)', () {
      final theme = buildReaderTheme(
        settings: const ReaderSettings(
          horizontalPadding: 16,
          verticalPadding: 32,
        ),
      );
      final bodyCss = theme.customCss!['body'] as Map<String, dynamic>;

      // Margins are now applied via setMargins() / hooks.render in JS,
      // not via the theme CSS, so padding should NOT be in body CSS.
      expect(bodyCss.containsKey('padding-left'), isFalse);
      expect(bodyCss.containsKey('padding-right'), isFalse);
      expect(bodyCss.containsKey('padding-top'), isFalse);
      expect(bodyCss.containsKey('padding-bottom'), isFalse);

      // But color rules should still be present.
      expect(bodyCss['background'], '#FFFFFF !important');
      expect(bodyCss['color'], '#000000 !important');
    });

    test('html CSS includes background and color', () {
      final theme = buildReaderTheme(settings: const ReaderSettings());
      final htmlCss = theme.customCss!['html'] as Map<String, dynamic>;

      expect(htmlCss['background'], '#FFFFFF !important');
      expect(htmlCss['color'], '#000000 !important');
    });
  });
}
