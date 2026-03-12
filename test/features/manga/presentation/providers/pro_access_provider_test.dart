import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/data/services/ocr_billing_client.dart';
import 'package:mekuru/features/manga/presentation/providers/pro_access_provider.dart';

class _FakeBillingClient extends OcrBillingClient {
  _FakeBillingClient({
    this.refreshedStatus,
    this.refreshDue = true,
  });

  OcrBillingStatus? localStatus;
  final OcrBillingStatus? refreshedStatus;
  final bool refreshDue;
  Object? refreshError;

  int refreshCalls = 0;

  @override
  Future<OcrBillingStatus?> readLastKnownStatus() async {
    return localStatus;
  }

  @override
  Future<bool> isRefreshDue() async {
    return refreshDue;
  }

  @override
  Future<OcrBillingStatus?> refreshStatusIfAuthenticated({
    bool forceRefresh = false,
  }) async {
    refreshCalls++;
    if (refreshError != null) {
      throw refreshError!;
    }
    return refreshedStatus ?? localStatus;
  }

  @override
  void dispose() {}
}

void main() {
  tearDown(() {
    PreloadedProEntitlement.setInitialSnapshot(null);
  });

  test(
    'proUnlockedProvider uses the preloaded unlocked snapshot immediately',
    () {
      PreloadedProEntitlement.setInitialSnapshot(
        const OcrBillingCacheSnapshot(
          uid: 'user-1',
          ocrUnlocked: true,
          creditBalance: 500,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          ocrBillingClientProvider.overrideWithValue(_FakeBillingClient()),
        ],
      );
      addTearDown(container.dispose);

      final result = container.read(proUnlockedProvider);

      expect(result.requireValue, isTrue);
    },
  );

  test('refreshIfDue updates the provider when live status changes', () async {
    PreloadedProEntitlement.setInitialSnapshot(
      const OcrBillingCacheSnapshot(
        uid: 'user-1',
        ocrUnlocked: false,
        creditBalance: 0,
      ),
    );
    final billingClient = _FakeBillingClient(
      refreshedStatus: const OcrBillingStatus(
        ocrUnlocked: true,
        creditBalance: 500,
      ),
    );
    final container = ProviderContainer(
      overrides: [ocrBillingClientProvider.overrideWithValue(billingClient)],
    );
    addTearDown(container.dispose);

    expect(container.read(proUnlockedProvider).requireValue, isFalse);

    await container.read(proUnlockedProvider.notifier).refreshIfDue();

    expect(container.read(proUnlockedProvider).requireValue, isTrue);
    expect(billingClient.refreshCalls, 1);
  });

  test(
    'refreshIfDue skips network refresh when the cached snapshot is fresh',
    () async {
      PreloadedProEntitlement.setInitialSnapshot(
        const OcrBillingCacheSnapshot(
          uid: 'user-1',
          ocrUnlocked: true,
          creditBalance: 500,
        ),
      );
      final billingClient = _FakeBillingClient(
        refreshDue: false,
        refreshedStatus: const OcrBillingStatus(
          ocrUnlocked: false,
          creditBalance: 0,
        ),
      );
      final container = ProviderContainer(
        overrides: [ocrBillingClientProvider.overrideWithValue(billingClient)],
      );
      addTearDown(container.dispose);

      await container.read(proUnlockedProvider.notifier).refreshIfDue();

      expect(container.read(proUnlockedProvider).requireValue, isTrue);
      expect(billingClient.refreshCalls, 0);
    },
  );

  testWidgets(
    'preloaded unlocked snapshot does not render a transient locked state',
    (tester) async {
      PreloadedProEntitlement.setInitialSnapshot(
        const OcrBillingCacheSnapshot(
          uid: 'user-1',
          ocrUnlocked: true,
          creditBalance: 500,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ocrBillingClientProvider.overrideWithValue(
              _FakeBillingClient(refreshDue: false),
            ),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                final isUnlocked = proUnlockedValue(
                  ref.watch(proUnlockedProvider),
                );
                return Text(isUnlocked ? 'unlocked' : 'locked');
              },
            ),
          ),
        ),
      );

      expect(find.text('unlocked'), findsOneWidget);
      expect(find.text('locked'), findsNothing);
    },
  );
}
