import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/data/services/ocr_billing_client.dart';

void main() {
  test('describeOcrError maps App Check rate limiting to retry guidance', () {
    final error = FirebaseException(
      plugin: 'firebase_app_check',
      code: 'too-many-requests',
      message: 'Too many attempts.',
    );

    expect(
      describeOcrError(error),
      'Firebase App Check is temporarily rate limited. '
      'Wait a few minutes before trying again.',
    );
  });

  test(
    'describeOcrError maps App Check attestation failures to build guidance',
    () {
      final error = FirebaseException(
        plugin: 'firebase_app_check',
        code: 'unknown',
        message:
            'Error returned from API. code: 403 body: App attestation failed.',
      );

      expect(
        describeOcrError(error),
        'Firebase App Check failed for this build. '
        'If this is a local test build, enable the debug App Check provider.',
      );
    },
  );
}
