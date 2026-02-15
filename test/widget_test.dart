import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/app.dart';

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
}
