import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/stats/presentation/widgets/hero_stat_tile.dart';

void main() {
  Widget wrap(Widget child, {bool disableAnimations = false}) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Scaffold(body: child),
      ),
    );
  }

  group('HeroStatTile', () {
    testWidgets('counts up to the final formatted value', (tester) async {
      await tester.pumpWidget(
        wrap(
          HeroStatTile(
            label: 'Reading time',
            value: 200,
            formatter: (value) => '${value}m',
          ),
        ),
      );

      // Mid-flight it shows an intermediate number, not the final one.
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('200m'), findsNothing);

      await tester.pumpAndSettle();
      expect(find.text('200m'), findsOneWidget);
      expect(find.text('Reading time'), findsOneWidget);
    });

    testWidgets('falls back to the raw value without a formatter', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const HeroStatTile(label: 'Words', value: 7)),
      );
      await tester.pumpAndSettle();

      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('skips the count-up when animations are disabled', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const HeroStatTile(label: 'Characters', value: 4321),
          disableAnimations: true,
        ),
      );

      // No settle: the value must be final on the very first frame.
      expect(find.text('4321'), findsOneWidget);
    });

    testWidgets('does not replay the count-up on an unrelated rebuild', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const HeroStatTile(label: 'Characters', value: 500)),
      );
      await tester.pumpAndSettle();

      // Same tile, new label — the entrance animation is one-shot per open.
      await tester.pumpWidget(
        wrap(const HeroStatTile(label: 'Chars', value: 500)),
      );
      await tester.pump();

      expect(find.text('500'), findsOneWidget);
    });
  });
}
