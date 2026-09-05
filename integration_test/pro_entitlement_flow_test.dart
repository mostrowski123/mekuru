import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/manga/data/services/ocr_billing_client.dart';
import 'package:mekuru/features/manga/data/services/ocr_store_service.dart';
import 'package:mekuru/features/manga/presentation/screens/pro_upgrade_screen.dart';

import '../test/test_app.dart';
import 'test_helpers.dart';

/// Device-side regression coverage for the Play-first Pro entitlement:
/// the parts host unit tests cannot reach — the real secure-storage plugin,
/// billing initialization on a device, and the Pro screen's provider chain.
///
/// The CI emulator (google_atd) has no Play Store, so the store reports
/// unavailable; every assertion here must also hold on a Play-enabled local
/// emulator. That is why the owned-purchases sync (which may legitimately
/// clear the entitlement on a Play device) runs before the flag is seeded.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpProScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: buildLocalizedTestApp(
          home: const ProUpgradeScreen(source: 'test'),
        ),
      ),
    );
  }

  testWidgets('play entitlement flows from real secure storage into the '
      'Pro screen', (tester) async {
    final l10n = await loadExpectedL10n();
    final client = OcrBillingClient();
    addTearDown(() async {
      await client.setPlayEntitlement(false);
      client.dispose();
    });

    // Startup warmup must be safe on any device, with or without Play
    // billing (regression guard for the MEKURU-18 emulator crash class).
    await OcrStoreService.instance.initialize();
    await OcrStoreService.instance.syncOwnedPurchases();

    // The entitlement survives a round trip through the real secure-storage
    // plugin and composes into an unlocked snapshot for a fresh client, the
    // same way main() preloads it.
    await client.setPlayEntitlement(true);
    final freshClient = OcrBillingClient();
    expect(await freshClient.hasPlayEntitlement(), isTrue);
    await PreloadedProEntitlement.load(billingClient: freshClient);
    expect(PreloadedProEntitlement.isInitiallyUnlocked, isTrue);
    freshClient.dispose();

    // An entitled install shows the Pro banner and no purchase button —
    // without any account, sign-in, or server round trip.
    await pumpProScreen(tester);
    await pumpUntilVisible(tester, find.text(l10n.proActiveTitle));
    expect(find.text(l10n.proStatusUnlocked), findsOneWidget);
    // Scroll to the list's end (the self-host repo link sits below the
    // purchase-button slot) so "no purchase button" means absent, not
    // merely unbuilt on a short screen.
    await tester.scrollUntilVisible(
      find.text(l10n.proServerRepo),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byType(FilledButton), findsNothing);

    // Clearing the entitlement (what a refund convergence does) locks the
    // screen again and brings the purchase button back.
    await client.setPlayEntitlement(false);
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpProScreen(tester);
    await pumpUntilVisible(tester, find.text(l10n.proStatusLocked));
    expect(find.text(l10n.proActiveTitle), findsNothing);
    // The purchase button is the ListView's last child — on short screens
    // (the CI emulator) it is not built until scrolled into view.
    await tester.scrollUntilVisible(
      find.byType(FilledButton),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byType(FilledButton), findsOneWidget);
  });
}
