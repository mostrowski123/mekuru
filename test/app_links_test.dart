import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/config/app_links.dart';

void main() {
  test('public app links use the canonical HTTPS host', () {
    for (final link in [
      AppLinks.website,
      AppLinks.documentation,
      AppLinks.privacyPolicy,
    ]) {
      expect(link.scheme, 'https');
      expect(link.host, 'mekuru.matthew.moe');
    }
  });

  test('privacy policy link avoids the legacy Pages host and redirect', () {
    expect(
      AppLinks.privacyPolicy.toString(),
      'https://mekuru.matthew.moe/privacy',
    );
  });
}
