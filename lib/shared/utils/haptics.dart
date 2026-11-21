import 'dart:async';

import 'package:flutter/services.dart';

/// Centralised haptic feedback helpers.
///
/// Used in library and settings interactions (including the reader settings
/// sheets) — intentionally **not** used for reading gestures themselves
/// (page turns, word taps, swipes).
///
/// Each call fires and returns at once: nothing waits for a haptic.
class AppHaptics {
  static void light() => unawaited(HapticFeedback.lightImpact());
  static void medium() => unawaited(HapticFeedback.mediumImpact());
  static void heavy() => unawaited(HapticFeedback.heavyImpact());
  static void selection() => unawaited(HapticFeedback.selectionClick());
}
