import 'package:flutter/services.dart';

import 'file_dialog_fakes.dart';

/// Says the device has [bytes] free (`getFreeBytes` on `mekuru/android_saf`,
/// the space check before a download) until the test ends.
void mockFreeBytes(int bytes) => fakeChannel(
  const MethodChannel('mekuru/android_saf'),
  (call) => call.method == 'getFreeBytes' ? bytes : null,
);
