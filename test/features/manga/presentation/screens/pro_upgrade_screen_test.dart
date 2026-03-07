import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mekuru/features/manga/presentation/screens/pro_upgrade_screen.dart';

void main() {
  testWidgets('locked state shows Pro upgrade CTA and feature list', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ProUpgradeScreen(
            loadSnapshot: () async => const ProUpgradeSnapshot(
              isUnlocked: false,
              priceLabel: '\$0.99',
              servicesAvailable: true,
            ),
            purchaseUpgrade: () async => const ProUpgradeSnapshot(
              isUnlocked: true,
              priceLabel: '\$0.99',
              servicesAvailable: true,
            ),
            restoreUpgrade: () async => const ProUpgradeSnapshot(
              isUnlocked: false,
              priceLabel: '\$0.99',
              servicesAvailable: true,
            ),
            openSelfHostRepo: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(find.text('Pro'), findsOneWidget);
    expect(find.text('Unlock Pro \$0.99'), findsOneWidget);
    expect(find.text('Auto-Crop'), findsOneWidget);
    expect(find.text('Book Highlights'), findsOneWidget);
    expect(find.text('Custom OCR Server'), findsOneWidget);
    expect(
      find.textContaining(
        'page'
        ' credits',
      ),
      findsNothing,
    );
    expect(
      find.textContaining(
        'starter'
        ' credits',
      ),
      findsNothing,
    );
    expect(find.textContaining('subscription'), findsNothing);
  });

  testWidgets('unlocked state shows already unlocked', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ProUpgradeScreen(
            loadSnapshot: () async => const ProUpgradeSnapshot(
              isUnlocked: true,
              priceLabel: '\$0.99',
              servicesAvailable: true,
            ),
            openSelfHostRepo: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(find.text('Already Unlocked'), findsOneWidget);
    expect(find.text('Locked'), findsNothing);
    expect(find.text('Unlocked'), findsOneWidget);
  });

  testWidgets('auth throttling shows retry guidance', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ProUpgradeScreen(
            loadSnapshot: () async => const ProUpgradeSnapshot(
              isUnlocked: false,
              priceLabel: '\$0.99',
              servicesAvailable: true,
            ),
            purchaseUpgrade: () async {
              throw FirebaseAuthException(
                code: 'too-many-requests',
                message: 'Too many attempts.',
              );
            },
            openSelfHostRepo: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Unlock Pro \$0.99'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.text(
        'Too many recent sign-in attempts. Wait a few minutes, then try again.',
      ),
      findsOneWidget,
    );
  });
}
