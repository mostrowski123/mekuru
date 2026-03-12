import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/data/services/ocr_billing_client.dart';
import 'package:mekuru/features/manga/presentation/services/ocr_purchase_flow.dart';
import 'package:mekuru/features/settings/data/services/ocr_server_config.dart';

import '../../../../test_app.dart';

class _FakeBillingClient extends OcrBillingClient {
  _FakeBillingClient({this.localStatus, this.refreshedStatus});

  OcrBillingStatus? localStatus;
  final OcrBillingStatus? refreshedStatus;

  int refreshCalls = 0;

  @override
  Future<OcrBillingStatus?> readLastKnownStatus() async {
    return localStatus;
  }

  @override
  Future<OcrBillingStatus?> refreshStatusIfAuthenticated({
    bool forceRefresh = false,
  }) async {
    refreshCalls++;
    return refreshedStatus;
  }

  @override
  void dispose() {}
}

void main() {
  testWidgets('immediate OCR start succeeds from the last known Pro snapshot', (
    tester,
  ) async {
    var proOpens = 0;
    bool? result;
    final billingClient = _FakeBillingClient(
      localStatus: const OcrBillingStatus(
        ocrUnlocked: true,
        creditBalance: 500,
      ),
    );

    final flow = OcrPurchaseFlow(
      billingClient: billingClient,
      loadCustomServerBearerKey: () async => 'secret',
      openProUpgradeScreen: (_) async {
        proOpens++;
      },
    );

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: _FlowHarness(
          onRun: (context) async {
            result = await flow.ensureProAndCustomOcrReady(
              context,
              getServerUrl: () => 'https://custom.example',
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
    expect(proOpens, 0);
    expect(billingClient.refreshCalls, 0);
  });

  testWidgets('missing local snapshot still routes through Pro upgrade', (
    tester,
  ) async {
    var proOpens = 0;
    bool? result;
    final billingClient = _FakeBillingClient();

    final flow = OcrPurchaseFlow(
      billingClient: billingClient,
      loadCustomServerBearerKey: () async => 'secret',
      openProUpgradeScreen: (_) async {
        proOpens++;
        billingClient.localStatus = const OcrBillingStatus(
          ocrUnlocked: true,
          creditBalance: 500,
        );
      },
    );

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: _FlowHarness(
          onRun: (context) async {
            result = await flow.ensureProAndCustomOcrReady(
              context,
              getServerUrl: () => 'https://custom.example',
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
    expect(proOpens, 1);
    expect(billingClient.refreshCalls, 1);
  });

  testWidgets('locked users are routed to Pro before OCR can continue', (
    tester,
  ) async {
    var proOpens = 0;
    var readCount = 0;
    bool? result;

    final flow = OcrPurchaseFlow(
      readProUnlocked: () async => readCount++ > 0,
      loadCustomServerBearerKey: () async => 'secret',
      openProUpgradeScreen: (_) async {
        proOpens++;
      },
    );

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: _FlowHarness(
          onRun: (context) async {
            result = await flow.ensureProAndCustomOcrReady(
              context,
              getServerUrl: () => 'https://custom.example',
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
    expect(proOpens, 1);
  });

  testWidgets('built-in server selection is treated as not configured', (
    tester,
  ) async {
    var settingsOpens = 0;
    var configured = false;
    bool? result;

    final flow = OcrPurchaseFlow(
      readProUnlocked: () async => true,
      loadCustomServerBearerKey: () async => 'secret',
      openSettingsScreen: (_) async {
        settingsOpens++;
        configured = true;
      },
    );

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: _FlowHarness(
          onRun: (context) async {
            result = await flow.ensureProAndCustomOcrReady(
              context,
              getServerUrl: () =>
                  configured ? 'https://custom.example' : defaultOcrServerUrl,
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    expect(find.text('Custom OCR Server Required'), findsOneWidget);

    await tester.tap(find.text('Open Settings'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
    expect(settingsOpens, 1);
  });

  testWidgets('missing custom server key opens settings before continuing', (
    tester,
  ) async {
    var settingsOpens = 0;
    var hasKey = false;
    bool? result;

    final flow = OcrPurchaseFlow(
      readProUnlocked: () async => true,
      loadCustomServerBearerKey: () async => hasKey ? 'secret' : null,
      openSettingsScreen: (_) async {
        settingsOpens++;
        hasKey = true;
      },
    );

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: _FlowHarness(
          onRun: (context) async {
            result = await flow.ensureProAndCustomOcrReady(
              context,
              getServerUrl: () => 'https://custom.example',
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    expect(find.text('Custom Server Setup Required'), findsOneWidget);

    await tester.tap(find.text('Open Settings'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
    expect(settingsOpens, 1);
  });

  testWidgets('configured custom server returns immediately', (tester) async {
    var proOpens = 0;
    var settingsOpens = 0;
    bool? result;

    final flow = OcrPurchaseFlow(
      readProUnlocked: () async => true,
      loadCustomServerBearerKey: () async => 'secret',
      openProUpgradeScreen: (_) async {
        proOpens++;
      },
      openSettingsScreen: (_) async {
        settingsOpens++;
      },
    );

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: _FlowHarness(
          onRun: (context) async {
            result = await flow.ensureProAndCustomOcrReady(
              context,
              getServerUrl: () => 'https://custom.example',
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
    expect(proOpens, 0);
    expect(settingsOpens, 0);
  });
}

class _FlowHarness extends StatelessWidget {
  const _FlowHarness({required this.onRun});

  final Future<void> Function(BuildContext context) onRun;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => onRun(context),
          child: const Text('Start'),
        ),
      ),
    );
  }
}
