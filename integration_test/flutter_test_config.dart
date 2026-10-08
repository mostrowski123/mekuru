import 'dart:async';

import 'package:mekuru/core/platform/device_memory.dart';

/// `flutter test` runs every integration test file through this.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // CI's 2 GB emulator would otherwise be offered Low RAM mode: the offer
  // comes up over the library and its barrier takes a test's next tap.
  debugDeviceLowOnMemory = false;
  await testMain();
}
