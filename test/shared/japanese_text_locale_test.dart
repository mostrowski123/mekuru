import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/dictionary/presentation/widgets/hit_testable_rich_text.dart';
import 'package:mekuru/features/dictionary/presentation/widgets/tappable_expression_text.dart';
import 'package:mekuru/shared/theme/app_theme.dart';

import '../test_app.dart';

// Kanji like 直, 骨 and 角 are drawn differently by Chinese and Japanese
// fonts. These tests keep every way Mekuru draws text on the Japanese one.

/// The root span style a [RichText] hands to its paragraph for [text]; every
/// span inherits its locale and font family.
TextStyle? _rootStyle(WidgetTester tester, String text) {
  final richText = tester.widget<RichText>(
    find.byWidgetPredicate(
      (widget) => widget is RichText && widget.text.toPlainText() == text,
    ),
  );
  return richText.text.style;
}

Widget _app({required Widget home, required Locale locale}) =>
    buildLocalizedTestApp(
      theme: AppTheme.lightTheme(AppColorTheme.mekuruRed.seedColor),
      locale: locale,
      home: Scaffold(body: home),
    );

const _uiLocales = [
  Locale('en'),
  Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every theme text style carries the Japanese locale and font', () {
    final seed = AppColorTheme.mekuruRed.seedColor;
    for (final theme in [
      AppTheme.lightTheme(seed),
      AppTheme.darkTheme(seed),
      AppTheme.darkTheme(seed, pureBlack: true),
    ]) {
      final textTheme = theme.textTheme;
      final styles = [
        textTheme.displayLarge,
        textTheme.displayMedium,
        textTheme.displaySmall,
        textTheme.headlineLarge,
        textTheme.headlineMedium,
        textTheme.headlineSmall,
        textTheme.titleLarge,
        textTheme.titleMedium,
        textTheme.titleSmall,
        textTheme.bodyLarge,
        textTheme.bodyMedium,
        textTheme.bodySmall,
        textTheme.labelLarge,
        textTheme.labelMedium,
        textTheme.labelSmall,
      ];
      for (final style in styles) {
        expect(style?.locale, japaneseTextLocale);
        expect(style?.fontFamily, japaneseFontFamily);
        expect(style?.fontFamilyFallback, ['Roboto', 'sans-serif']);
      }
    }
  });

  test('iOS keeps the system fonts', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final style = AppTheme.lightTheme(
      AppColorTheme.mekuruRed.seedColor,
    ).textTheme.bodyMedium;
    expect(style?.locale, japaneseTextLocale);
    expect(style?.fontFamily, isNot(japaneseFontFamily));
  });

  test('the Japanese font is bundled under its family name', () async {
    // A family missing from pubspec.yaml fails silently on a phone: the
    // system font, with its Chinese forms, draws the kanji instead.
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json'))
            as List<dynamic>;
    final family = manifest.cast<Map<String, dynamic>>().singleWhere(
      (entry) => entry['family'] == japaneseFontFamily,
    );
    final fonts = (family['fonts'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(fonts, hasLength(2));
    for (final font in fonts) {
      final bytes = await rootBundle.load(font['asset'] as String);
      expect(bytes.lengthInBytes, greaterThan(1000000), reason: '$font');
    }
  });

  test('bare RichText and TextPainter start from japaneseTextStyle', () {
    // They skip DefaultTextStyle, so the theme's Japanese font and locale
    // never reach them: their style has to start from japaneseTextStyle (or
    // a theme text style) explicitly.
    // shortcut: checks per file, so a second bare painter in a file that
    // already uses the style slips through; a custom lint would catch it.
    final bare = RegExp(r'\b(RichText|TextPainter)\(');
    final offenders = [
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File && file.path.endsWith('.dart'))
          if (file.readAsStringSync() case final source
              when bare.hasMatch(source) &&
                  !source.contains('japaneseTextStyle') &&
                  !source.contains('.textTheme.'))
            file.path,
    ];
    expect(offenders, isEmpty);
  });

  for (final uiLocale in _uiLocales) {
    testWidgets('Text with its own style renders Japanese under a '
        '${uiLocale.toLanguageTag()} UI', (tester) async {
      await tester.pumpWidget(
        _app(
          locale: uiLocale,
          home: const Text('直す', style: TextStyle(fontSize: 24)),
        ),
      );

      expect(_rootStyle(tester, '直す')?.locale, japaneseTextLocale);
      expect(_rootStyle(tester, '直す')?.fontFamily, japaneseFontFamily);
    });

    testWidgets('dictionary headword renders Japanese under a '
        '${uiLocale.toLanguageTag()} UI', (tester) async {
      // The entry card builds its headword style from scratch, and a bare
      // RichText does not inherit the theme through DefaultTextStyle.
      await tester.pumpWidget(
        _app(
          locale: uiLocale,
          home: TappableExpressionText(
            expression: '直す',
            reading: '',
            expressionStyle: const TextStyle(fontSize: 24),
            onKanjiTap: (_) {},
          ),
        ),
      );

      expect(find.byType(HitTestableRichText), findsOneWidget);
      expect(_rootStyle(tester, '直す')?.locale, japaneseTextLocale);
      expect(_rootStyle(tester, '直す')?.fontFamily, japaneseFontFamily);
    });
  }
}
