import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/app.dart';
import 'package:mekuru/features/settings/data/services/app_settings_storage.dart';
import 'package:mekuru/features/stats/presentation/providers/stats_providers.dart';
import 'package:mekuru/features/stats/presentation/screens/stats_screen.dart';
import 'package:mekuru/features/you/presentation/screens/you_screen.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/l10n/l10n.dart';

import 'test_app.dart';

void main() {
  testWidgets('App smoke test shows bottom navigation', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: MekuruApp()));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Library'), findsWidgets);
    expect(find.text('Dictionary'), findsOneWidget);
    expect(find.text('Vocabulary'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('You tab is a hub of Free books, Reading stats and Settings', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionsProvider.overrideWith((ref) => Stream.value(const [])),
          wordEventsProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: const MekuruApp(),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Settings has no navigation-bar slot; it lives on the You hub.
    expect(find.text('Settings'), findsNothing);

    await tester.tap(find.text('You'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(YouScreen), findsOneWidget);
    expect(find.text('Free books'), findsOneWidget);
    expect(find.text('Reading stats'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('0m this week'), findsOneWidget);

    await tester.tap(find.text('Reading stats'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(StatsScreen), findsOneWidget);
  });

  testWidgets('leaving the You tab unmounts the hub', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionsProvider.overrideWith((ref) => Stream.value(const [])),
          wordEventsProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: const MekuruApp(),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('You'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(YouScreen, skipOffstage: false), findsOneWidget);

    // The hub re-aggregates the week on every session write; the
    // IndexedStack must not keep it doing that invisibly after the user
    // switches away.
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Library'),
      ),
    );
    await tester.pump();
    expect(find.byType(YouScreen, skipOffstage: false), findsNothing);
  });

  testWidgets('Spanish locale resolves localized navigation labels', (
    WidgetTester tester,
  ) async {
    final locale = const Locale('es');
    final l10n = await AppLocalizations.delegate.load(locale);

    await tester.pumpWidget(
      buildLocalizedTestApp(
        locale: locale,
        home: const Scaffold(body: _NavLabelProbe()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text(l10n.navLibrary), findsOneWidget);
  });

  testWidgets(
    'Simplified Chinese locale resolves localized navigation labels',
    (WidgetTester tester) async {
      final locale = const Locale.fromSubtags(
        languageCode: 'zh',
        scriptCode: 'Hans',
      );
      final l10n = await AppLocalizations.delegate.load(locale);

      await tester.pumpWidget(
        buildLocalizedTestApp(
          locale: locale,
          home: const Scaffold(body: _NavLabelProbe()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text(l10n.navLibrary), findsOneWidget);
    },
  );

  test(
    'Chinese locale with CN country resolves to Simplified Chinese support',
    () {
      expect(
        resolveSupportedAppLocale(
          const Locale.fromSubtags(languageCode: 'zh', countryCode: 'CN'),
          AppLocalizations.supportedLocales,
        ),
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      );
    },
  );

  test('Traditional Chinese locale falls back to English support', () {
    expect(
      resolveSupportedAppLocale(
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
        AppLocalizations.supportedLocales,
      ),
      const Locale('en'),
    );
  });

  testWidgets('Unsupported locale falls back to English', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      buildLocalizedTestApp(
        locale: const Locale('fr'),
        home: const Scaffold(body: _NavLabelProbe()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Library'), findsOneWidget);
  });
}

class _NavLabelProbe extends StatelessWidget {
  const _NavLabelProbe();

  @override
  Widget build(BuildContext context) {
    return Text(context.l10n.navLibrary);
  }
}
