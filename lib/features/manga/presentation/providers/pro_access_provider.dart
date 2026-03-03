import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/ocr_billing_client.dart';

final proUnlockedProvider = FutureProvider<bool>((ref) async {
  if (kDebugMode) return true;

  final billingClient = OcrBillingClient();
  try {
    final status = await billingClient.readCachedStatus();
    return status?.ocrUnlocked ?? false;
  } catch (_) {
    return false;
  } finally {
    billingClient.dispose();
  }
});

bool proUnlockedValue(AsyncValue<bool> value) {
  return value.maybeWhen(data: (isUnlocked) => isUnlocked, orElse: () => false);
}
