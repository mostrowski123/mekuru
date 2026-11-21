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

    testWidgets('keeps the number at a large text size and wraps it', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: Scaffold(
              body: Center(
                // A third of a 360-wide phone, past the row's padding.
                child: SizedBox(
                  width: 110,
                  child: HeroStatTile(
                    label: 'Reading time',
                    value: 7245,
                    formatter: (m) => '${m ~/ 60}h ${m % 60}m',
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // Painted at the size it was laid out at, so nothing scaled it down.
      final number = find.text('120h 45m');
      expect(tester.getRect(number).size, tester.getSize(number));
      expect(tester.takeException(), isNull);
    });
  });
}
