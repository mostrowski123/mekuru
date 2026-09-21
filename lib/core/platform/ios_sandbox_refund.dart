import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('mekuru/sandbox_refund');

/// Whether [productId] was bought with test money (TestFlight, a sandbox
/// Apple Account, Xcode) and is not refunded yet. `AppDelegate.swift` reads
/// this from the transaction's own environment, so it is false for every App
/// Store customer. A sandbox purchase is in no purchase history: Apple's
/// refund sheet is the only way a tester can refund one.
Future<bool> canRequestSandboxRefund(String productId) async {
  if (defaultTargetPlatform != TargetPlatform.iOS) return false;
  try {
    return await _channel.invokeMethod<bool>('canRequest', productId) ?? false;
  } catch (_) {
    return false;
  }
}

/// Shows Apple's refund sheet for [productId]: true when the request was
/// sent, false when the tester closed the sheet. The sandbox approves every
/// reason, except "Other" with the text DECLINE, which it declines.
Future<bool> requestSandboxRefund(String productId) async =>
    await _channel.invokeMethod<bool>('request', productId) ?? false;
