import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/platform/device_memory.dart';

void main() {
  test('RAM is banded in whole GB, as the device is sold', () {
    expect(ramBand(2790), '3');
    expect(ramBand(3712), '4');
    expect(ramBand(4096), '4');
    expect(ramBand(5600), '6');
    expect(ramBand(7540), '8');
  });

  test('exit reasons are named; a newer one stays a number', () {
    expect(processExitReasonName(0), 'unknown');
    expect(processExitReasonName(3), 'low_memory');
    expect(processExitReasonName(16), 'package_updated');
    expect(processExitReasonName(17), '17');
  });
}
