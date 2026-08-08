import 'package:flutter/foundation.dart' show listEquals, setEquals;

/// The optimistic post-drag order a reorderable list shows while the
/// reorder write's stream echo is in flight, or null once [stream] has
/// caught up.
///
/// [local] only holds while [stream] contains the same items in a
/// different order; once the echo lands (same order) it retires, and any
/// membership change (different items) wins immediately. Retiring on the
/// echo — instead of when the write completes — is what keeps the list
/// from rebuilding in the stale order for a few frames and visibly
/// replaying the drop animation.
///
/// Call this from build and assign the result back to the field: a
/// retained non-null local would override a later external reorder. Items
/// are compared by [id], not `==` — Drift data classes compare every
/// column, and an unrelated field change (say, read progress) must not
/// keep the override alive.
List<T>? pendingDragOrder<T>(
  List<T>? local,
  List<T> stream,
  Object Function(T) id,
) {
  if (local == null) return null;
  final localIds = [for (final item in local) id(item)];
  final streamIds = [for (final item in stream) id(item)];
  if (listEquals(localIds, streamIds)) return null; // echo landed
  return setEquals(localIds.toSet(), streamIds.toSet()) ? local : null;
}
