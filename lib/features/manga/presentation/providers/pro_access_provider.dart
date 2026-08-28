import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/ocr_billing_client.dart';

final ocrBillingClientProvider = Provider<OcrBillingClient>((ref) {
  final client = OcrBillingClient();
  ref.onDispose(client.dispose);
  return client;
});

class ProUnlockedNotifier extends AsyncNotifier<bool> {
  @override
  FutureOr<bool> build() {
    ref.watch(ocrBillingClientProvider);
    return PreloadedProEntitlement.isInitiallyUnlocked;
  }

  Future<void> refreshIfDue() async {
    final billingClient = ref.read(ocrBillingClientProvider);
    if (!await billingClient.isRefreshDue()) {
      return;
    }
    if (!ref.mounted) {
      return;
    }
    await _refresh(forceRefresh: false);
  }

  Future<void> forceRefresh() {
    return _refresh(forceRefresh: true);
  }

  Future<void> _refresh({required bool forceRefresh}) async {
    final billingClient = ref.read(ocrBillingClientProvider);
    final currentValue =
        state.asData?.value ?? PreloadedProEntitlement.isInitiallyUnlocked;
    try {
      final status = await billingClient.refreshStatusIfAuthenticated(
        forceRefresh: forceRefresh,
      );
      if (!ref.mounted) {
        return;
      }
      if (status == null) {
        state = AsyncData(currentValue);
        return;
      }
      // Already composed with the play entitlement by the billing client.
      state = AsyncData(status.ocrUnlocked);
    } catch (_) {
      if (!ref.mounted) {
        return;
      }
      state = AsyncData(currentValue);
    }
  }
}

final proUnlockedProvider = AsyncNotifierProvider<ProUnlockedNotifier, bool>(
  ProUnlockedNotifier.new,
);

bool proUnlockedValue(AsyncValue<bool> value) {
  return value.maybeWhen(data: (isUnlocked) => isUnlocked, orElse: () => false);
}
