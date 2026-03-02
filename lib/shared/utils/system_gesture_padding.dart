import 'package:flutter/widgets.dart';

/// Returns additional bottom padding for controls placed inside a [SafeArea].
///
/// [SafeArea] already accounts for [MediaQueryData.padding]. This helper adds a
/// small baseline gap plus any extra clearance needed when the system gesture
/// zone extends beyond that safe-area inset.
double bottomControlPadding(
  MediaQueryData mediaQueryData, {
  double minimumPadding = 8.0,
  double gestureClearance = 8.0,
}) {
  final safeInset = mediaQueryData.padding.bottom;
  final gestureInset = mediaQueryData.systemGestureInsets.bottom;
  final gesturePadding = gestureInset > safeInset
      ? (gestureInset - safeInset) + gestureClearance
      : 0.0;

  return gesturePadding > minimumPadding ? gesturePadding : minimumPadding;
}
