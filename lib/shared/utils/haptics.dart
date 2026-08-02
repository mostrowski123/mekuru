import 'package:flutter/services.dart';

/// Centralised haptic feedback helpers.
///
/// Used in library and settings interactions (including the reader settings
/// sheets) — intentionally **not** used for reading gestures themselves
/// (page turns, word taps, swipes).
class AppHaptics {
  static Future<void> light() => HapticFeedback.lightImpact();
  static Future<void> medium() => HapticFeedback.mediumImpact();
  static Future<void> heavy() => HapticFeedback.heavyImpact();
  static Future<void> selection() => HapticFeedback.selectionClick();
}
