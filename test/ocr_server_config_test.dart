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

    // Uri percent-encodes what a host can't hold instead of rejecting it, and
    // dart:io then throws a FormatException on the `%` before sending
    // (Sentry: `%3C192.168.1.5%3E is not a valid link-local address`).
    test('tryParseOcrServerUrl rejects hosts Uri had to escape', () {
      expect(tryParseOcrServerUrl('http://<192.168.1.5>:5000'), isNull);
      expect(tryParseOcrServerUrl('http://my server:5000'), isNull);
    });

    test('tryParseOcrServerUrl keeps IPv6 literals', () {
      expect(tryParseOcrServerUrl('http://[::1]:8000'), isNotNull);
      expect(tryParseOcrServerUrl('http://[fe80::1%25en0]:8000'), isNotNull);
    });

    test('validateOcrServerUrl returns helpful errors', () {
      expect(validateOcrServerUrl(''), 'Enter your server URL.');
      expect(
        validateOcrServerUrl('not-a-url'),
        'Enter a full http:// or https:// server URL.',
      );
      expect(
        validateOcrServerUrl('http://<192.168.1.5>:5000'),
        'Remove spaces and symbols like < > from the server address.',
      );
      expect(validateOcrServerUrl('https://ocr.example.com'), isNull);
      expect(validateOcrServerUrl('', allowEmpty: true), isNull);
    });
  });
}
