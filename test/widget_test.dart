import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/app.dart';
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

  testWidgets('Japanese locale resolves localized navigation labels', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      buildLocalizedTestApp(
        locale: const Locale('ja'),
        home: const Scaffold(body: _NavLabelProbe()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('ライブラリ'), findsOneWidget);
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
