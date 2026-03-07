import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/ocr_billing_client.dart';

final ocrBillingClientProvider = Provider<OcrBillingClient>((ref) {
  final client = OcrBillingClient();
  ref.onDispose(client.dispose);
  return client;
});

final proUnlockedProvider = FutureProvider<bool>((ref) async {
  final billingClient = ref.watch(ocrBillingClientProvider);
  try {
    // Passive UI checks should not create anonymous Firebase users. Use the
    // cached entitlement first and only refresh from the server when a real
    // Firebase session already exists.
    final status = await billingClient.fetchStatusIfAuthenticated();
    return status?.ocrUnlocked ?? false;
  } catch (_) {
    return false;
  }
});

bool proUnlockedValue(AsyncValue<bool> value) {
  return value.maybeWhen(data: (isUnlocked) => isUnlocked, orElse: () => false);
}
