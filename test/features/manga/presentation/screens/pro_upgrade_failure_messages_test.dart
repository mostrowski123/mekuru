import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:mekuru/core/platform/capabilities.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/manga/data/services/ocr_store_service.dart';
import 'package:mekuru/features/manga/presentation/screens/pro_upgrade_screen.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../test_app.dart';

/// Stands for whatever an exception says that the user must never read.
const _secret = 'BillingClient debug message';

/// The store behind InAppPurchase.instance, which the screen's own store
/// service talks to when no snapshot is handed in.
class _Store extends InAppPurchasePlatform {
  Object? availableError;
  Object? queryError;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => const Stream.empty();

  @override
  Future<bool> isAvailable() async {
    if (availableError case final error?) throw error;
    return true;
  }

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async {
    if (queryError case final error?) throw error;
    return ProductDetailsResponse(productDetails: const [], notFoundIDs: []);
  }
}

void main() {
  final ja = lookupAppLocalizations(const Locale('ja'));
  final store = _Store();
  final logs = <String>[];

  setUpAll(() {
    // The store service's first use builds InAppPurchase.instance, which on
    // Android or iOS registers the real store, whose connection fails in a
    // test. Built for another platform it registers none, and this one
    // stands in.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      expect(OcrStoreService.instance.isStoreAvailable, isFalse);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
    InAppPurchasePlatform.instance = store;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store
      ..availableError = null
      ..queryError = null;
    logs.clear();
    usageLogSinkOverride = (message, _, {required isWarning}) =>
        logs.add(message);
    usageAnalyticsSinkOverride = (_, _) {};
    usageIssueSinkOverride = (_, _) {};
  });

  tearDown(() {
    usageLogSinkOverride = null;
    usageAnalyticsSinkOverride = null;
    usageIssueSinkOverride = null;
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    Future<ProUpgradeSnapshot> Function()? loadSnapshot,
    Future<ProUpgradeSnapshot> Function()? purchaseUpgrade,
    Future<ProUpgradeSnapshot> Function()? restoreUpgrade,
  }) async {
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: buildLocalizedTestApp(
          locale: const Locale('ja'),
          home: ProUpgradeScreen(
            source: 'test',
            loadSnapshot: loadSnapshot,
            purchaseUpgrade: purchaseUpgrade,
            restoreUpgrade: restoreUpgrade,
            forceServicesAvailable: true,
            canRequestSandboxRefund: () async => false,
            openSelfHostRepo: () async {},
          ),
        ),
      ),
    );
    // The default load waits on plugin channels that answer outside the
    // test's clock.
    for (var i = 0; i < 50; i++) {
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  void expectOnlyWorded(String message, {required String leaked}) {
    expect(find.textContaining(leaked), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.text(message), findsOneWidget);
  }

  // The store service is one for the whole run and stops asking once the
  // store has answered, so the unreachable store comes first.
  testWidgets('a store that cannot be reached says so in Japanese', (
    tester,
  ) async {
    store.availableError = StateError(_secret);
    await pumpScreen(tester);

    expectOnlyWorded(ja.proErrorStore(store: storeName), leaked: _secret);
    expect(logs, contains('pro.store_init_failed'));
  });

  testWidgets('a price that cannot be loaded says so in Japanese', (
    tester,
  ) async {
    store.queryError = PlatformException(code: 'error', message: _secret);
    await pumpScreen(tester);

    expectOnlyWorded(ja.proErrorStore(store: storeName), leaked: _secret);
    expect(logs, contains('pro.price_load_failed'));
  });

  group('with a locked snapshot', () {
    Future<ProUpgradeSnapshot> locked() async => const ProUpgradeSnapshot(
      isUnlocked: false,
      priceLabel: r'$0.99',
      servicesAvailable: true,
    );

    Future<void> tapAndShow(WidgetTester tester, Finder button) async {
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    }

    testWidgets('a purchase that fails with no words of its own says the '
        'request did not go through', (tester) async {
      await pumpScreen(
        tester,
        loadSnapshot: locked,
        purchaseUpgrade: () async => throw StateError(_secret),
      );

      await tapAndShow(
        tester,
        find.widgetWithText(
          FilledButton,
          ja.proUnlockWithPrice(price: r'$0.99'),
        ),
      );

      expectOnlyWorded(ja.serverErrorUnknown, leaked: _secret);
      expect(logs.where((e) => e == 'pro.purchase_failed'), hasLength(1));
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a restore that fails with no words of its own says so and '
        'is logged', (tester) async {
      await pumpScreen(
        tester,
        loadSnapshot: locked,
        restoreUpgrade: () async => throw StateError(_secret),
      );

      await tapAndShow(tester, find.byIcon(Icons.refresh));

      expectOnlyWorded(ja.serverErrorUnknown, leaked: _secret);
      expect(logs, contains('pro.restore_failed'));
      await tester.pump(const Duration(seconds: 5));
    });
  });
}
