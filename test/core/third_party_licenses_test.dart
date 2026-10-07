import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/services/third_party_licenses.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every third-party notice is bundled and has its text', () async {
    final packages = <String>[];
    await for (final entry in thirdPartyLicenseEntries()) {
      packages.addAll(entry.packages);
      expect(
        entry.paragraphs.map((p) => p.text).join(),
        contains(RegExp('copyright|license', caseSensitive: false)),
        reason: entry.packages.single,
      );
    }
    expect(packages, thirdPartyLicenses.keys);
  });
}
