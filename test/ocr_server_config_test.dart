import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/settings/data/services/ocr_server_config.dart';

void main() {
  group('ocr_server_config', () {
    test('normalizeOcrServerUrl trims whitespace and trailing slashes', () {
      expect(
        normalizeOcrServerUrl('  https://ocr.example.com/api/  '),
        'https://ocr.example.com/api',
      );
    });

    test('tryParseOcrServerUrl accepts http and https URLs', () {
      expect(tryParseOcrServerUrl('https://ocr.example.com'), isNotNull);
      expect(tryParseOcrServerUrl('http://192.168.1.5:8000'), isNotNull);
    });

    test('tryParseOcrServerUrl rejects invalid or unsupported URLs', () {
      expect(tryParseOcrServerUrl(''), isNull);
      expect(tryParseOcrServerUrl('ocr.example.com'), isNull);
      expect(tryParseOcrServerUrl('ftp://ocr.example.com'), isNull);
    });

    test('validateOcrServerUrl returns helpful errors', () {
      expect(validateOcrServerUrl(''), 'Enter your server URL.');
      expect(
        validateOcrServerUrl('not-a-url'),
        'Enter a full http:// or https:// server URL.',
      );
      expect(validateOcrServerUrl('https://ocr.example.com'), isNull);
      expect(validateOcrServerUrl('', allowEmpty: true), isNull);
    });
  });
}
