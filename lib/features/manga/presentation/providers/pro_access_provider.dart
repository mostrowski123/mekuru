import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/ocr_billing_client.dart';

final proUnlockedProvider = FutureProvider<bool>((ref) async {
  final billingClient = OcrBillingClient();
  try {
    // fetchStatus() reads from secure-storage cache first.  If the cache is
    // stale (>24 h) or missing it transparently fetches from the server and
    // refreshes the cache, so the provider always returns up-to-date data
    // without extra boilerplate here.
    final status = await billingClient.fetchStatus();
    return status.ocrUnlocked;
  } catch (_) {
    return false;
  } finally {
    billingClient.dispose();
  }
});

bool proUnlockedValue(AsyncValue<bool> value) {
  return value.maybeWhen(data: (isUnlocked) => isUnlocked, orElse: () => false);
}
