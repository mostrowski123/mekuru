import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/manga/data/services/ocr_account_link_service.dart';
import 'package:mekuru/features/manga/data/services/ocr_billing_client.dart';
import 'package:mekuru/features/manga/presentation/screens/pro_upgrade_screen.dart';
import 'package:mekuru/features/settings/presentation/widgets/ocr_attributions.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../test_app.dart';

const _lockedSnapshot = ProUpgradeSnapshot(
  isUnlocked: false,
  priceLabel: '\$0.99',
  servicesAvailable: true,
);

/// Captures every usage-telemetry log as `<level>:<event>` (plus any
/// `stage`/`result` attribute as `(<key>=<value>)`) for the current test.
List<String> captureUsageLogs() {
  final logged = <String>[];
  usageLogSinkOverride = (message, attributes, {required isWarning}) {
    final details = [
      for (final key in const ['stage', 'result'])
        if (attributes[key] != null) '$key=${attributes[key]!.value}',
    ].join(',');
    logged.add(
      '${isWarning ? 'warn' : 'info'}:$message'
      '${details.isEmpty ? '' : '($details)'}',
    );
  };
  addTearDown(() => usageLogSinkOverride = null);
  return logged;
}

Future<void> pumpLockedScreen(
  WidgetTester tester, {
  Future<ProUpgradeSnapshot> Function()? purchaseUpgrade,
  Future<ProUpgradeSnapshot> Function()? restoreUpgrade,
}) async {
  // The screen outgrew one default test viewport; a tall surface keeps every
  // card and button built so the fixed drag below cannot dispose them.
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: buildLocalizedTestApp(
        home: ProUpgradeScreen(
          source: 'test',
          loadSnapshot: () async => _lockedSnapshot,
          purchaseUpgrade: purchaseUpgrade,
          restoreUpgrade: restoreUpgrade,
          openSelfHostRepo: () async {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.drag(find.byType(ListView), const Offset(0, -600));
  await tester.pumpAndSettle();
}

Future<void> tapAndSettleSnackBar(WidgetTester tester, Finder button) async {
  await tester.tap(button);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'locked state warns about on-device OCR and offers the speed test',
    (tester) async {
      final opened = <Uri>[];
      await tester.pumpWidget(
        ProviderScope(
          child: buildLocalizedTestApp(
            home: ProUpgradeScreen(
              source: 'test',
              loadSnapshot: () async => _lockedSnapshot,
              openSelfHostRepo: () async {},
              launchExternalUrl: (url) async => opened.add(url),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Test device speed'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('On-device OCR'), findsOneWidget);
      // The card names the models and links to their repositories.
      expect(
        find.textContaining("kha-white's manga-ocr model"),
        findsOneWidget,
      );
      // The list only builds the links within its cache extent; bring them
      // on screen before tapping.
      for (final name in ['manga-ocr', 'Comic Text Detector']) {
        await tester.ensureVisible(find.text(name));
        await tester.pumpAndSettle();
        await tester.tap(find.text(name));
      }
      expect(opened.map((u) => u.toString()), [
        OcrAttributions.mangaOcrRepoUrl,
        OcrAttributions.detectorRepoUrl,
      ]);
      expect(
        find.textContaining('Test your device before you buy'),
        findsOneWidget,
      );
      // Buy stays the only FilledButton; the test button is outlined.
      expect(
        find.widgetWithText(OutlinedButton, 'Test device speed'),
        findsOneWidget,
      );
    },
  );

  testWidgets('locked state shows Pro upgrade CTA and feature list', (
    tester,
  ) async {
    await pumpLockedScreen(
      tester,
      purchaseUpgrade: () async => const ProUpgradeSnapshot(
        isUnlocked: true,
        priceLabel: '\$0.99',
        servicesAvailable: true,
      ),
      restoreUpgrade: () async => _lockedSnapshot,
    );

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

  testWidgets('on-device OCR is offered on Android only', (tester) async {
    await pumpLockedScreen(tester);
    expect(find.text('On-device OCR'), findsOneWidget);

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await pumpLockedScreen(tester);
      expect(find.text('On-device OCR'), findsNothing);
      expect(find.text('Comic Text Detector'), findsNothing);
      expect(find.text('Custom OCR Server'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('unlocked state shows the Pro-active banner and no buy button', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: buildLocalizedTestApp(
          home: ProUpgradeScreen(
            source: 'test',
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

    expect(find.text('You have Mekuru Pro'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.text('Locked'), findsNothing);
    expect(find.text('Unlocked'), findsOneWidget);
  });

  testWidgets('auth throttling shows retry guidance', (tester) async {
    await pumpLockedScreen(
      tester,
      purchaseUpgrade: () async {
        throw FirebaseAuthException(
          code: 'too-many-requests',
          message: 'Too many attempts.',
        );
      },
    );

    await tapAndSettleSnackBar(tester, find.text('Unlock Pro \$0.99'));

    expect(
      find.text(
        'Too many recent sign-in attempts. Wait a few minutes, then try again.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('cancelling Google sign-in counts as cancellation, not failure', (
    tester,
  ) async {
    final logged = captureUsageLogs();
    await pumpLockedScreen(
      tester,
      purchaseUpgrade: () async {
        throw const AccountLinkCancelledException();
      },
    );

    await tapAndSettleSnackBar(tester, find.text('Unlock Pro \$0.99'));

    expect(find.text('Google sign-in was cancelled.'), findsOneWidget);
    expect(logged, contains('info:pro.purchase_cancelled(stage=signin)'));
    expect(logged, isNot(contains('warn:pro.purchase_failed')));
  });

  testWidgets('cancelling the billing sheet logs the billing stage', (
    tester,
  ) async {
    final logged = captureUsageLogs();
    await pumpLockedScreen(
      tester,
      purchaseUpgrade: () async {
        throw const OcrBillingException(
          409,
          'The purchase was cancelled.',
          code: 'purchase_cancelled',
        );
      },
    );

    await tapAndSettleSnackBar(tester, find.text('Unlock Pro \$0.99'));

    expect(logged, contains('info:pro.purchase_cancelled(stage=billing)'));
    expect(logged, isNot(contains('warn:pro.purchase_failed')));
  });

  testWidgets('cancelling Google sign-in during restore is not an error', (
    tester,
  ) async {
    final logged = captureUsageLogs();
    await pumpLockedScreen(
      tester,
      restoreUpgrade: () async {
        throw const AccountLinkCancelledException();
      },
    );

    await tapAndSettleSnackBar(tester, find.byIcon(Icons.refresh));

    expect(find.text('Google sign-in was cancelled.'), findsOneWidget);
    expect(logged, contains('info:pro.restore(result=cancelled)'));
    expect(logged, isNot(contains('info:pro.restore(result=error)')));
  });
}
