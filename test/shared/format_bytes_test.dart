import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/shared/utils/format_bytes.dart';

void main() {
  test('formatBytes picks the unit and precision people expect', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(1024 * 1024), '1.0 MB');
    expect(formatBytes(150 * 1024 * 1024), '150 MB');
    expect(formatBytes(5 * 1024 * 1024 * 1024), '5.0 GB');
    expect(formatBytes(12 * 1024 * 1024 * 1024 + 1), '12.0 GB');
  });
}
