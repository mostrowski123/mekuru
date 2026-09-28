import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/dictionary/presentation/widgets/hit_testable_rich_text.dart';
import 'package:mekuru/features/dictionary/presentation/widgets/tappable_expression_text.dart';
import 'package:mekuru/features/settings/data/services/app_settings_storage.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/shared/theme/app_theme.dart';

/// The locale a [RichText] hands to its paragraph for [text]: the span's own
/// style locale wins over the widget-level default.
Locale? _effectiveLocale(WidgetTester tester, String text) {
  final richText = tester.widget<RichText>(
    find.byWidgetPredicate(
      (widget) => widget is RichText && widget.text.toPlainText() == text,
    ),
  );
  return richText.text.style?.locale ?? richText.locale;
}

Widget _app({required Widget home, required Locale locale}) {
  return MaterialApp(
    theme: AppTheme.lightTheme(AppColorTheme.mekuruRed.seedColor),
    locale: locale,
    localeResolutionCallback: resolveSupportedAppLocale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: home),
  );
}

const _uiLocales = [
  Locale('en'),
  Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
];

void main() {
  test('every theme text style carries the Japanese locale', () {
    final seed = AppColorTheme.mekuruRed.seedColor;
    for (final theme in [AppTheme.lightTheme(seed), AppTheme.darkTheme(seed)]) {
      for (final textTheme in [theme.textTheme, theme.primaryTextTheme]) {
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
        }
      }
    }
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

      expect(_effectiveLocale(tester, '直す'), japaneseTextLocale);
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
      expect(_effectiveLocale(tester, '直す'), japaneseTextLocale);
    });
  }

  testWidgets('dictionary headword with furigana renders Japanese', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        locale: const Locale('en'),
        home: TappableExpressionText(
          expression: '直す',
          reading: 'なおす',
          expressionStyle: const TextStyle(fontSize: 24),
          furiganaStyle: const TextStyle(fontSize: 12),
          onKanjiTap: (_) {},
        ),
      ),
    );

    expect(_effectiveLocale(tester, '直'), japaneseTextLocale);
    expect(_effectiveLocale(tester, 'なお'), japaneseTextLocale);
  });

  testWidgets('HitTestableRichText pins the Japanese locale', (tester) async {
    await tester.pumpWidget(
      _app(
        locale: const Locale('en'),
        home: HitTestableRichText(
          text: const TextSpan(text: '直す', style: TextStyle(fontSize: 24)),
          targets: const [],
          onTapTarget: (_) {},
        ),
      ),
    );

    expect(_effectiveLocale(tester, '直す'), japaneseTextLocale);
  });
}
