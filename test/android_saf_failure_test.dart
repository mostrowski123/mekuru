import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/platform/android_saf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('mekuru/android_saf');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Makes the SAF channel fail every call with [error].
  void stubFailure(PlatformException error) {
    messenger.setMockMethodCallHandler(channel, (_) async => throw error);
  }

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('AndroidSafFailure — parsing', () {
    test('carries code, message, authority and stage from the platform', () {
      final failure = AndroidSafFailure.fromPlatformException(
        'readBytesFromTreePath',
        PlatformException(
          code: 'saf_document_not_found',
          message: 'No document matching the requested path exists',
          details: {
            'authority': 'com.android.providers.downloads.documents',
            'stage': 'resolve',
          },
        ),
      );

      expect(failure.operation, 'readBytesFromTreePath');
      expect(failure.code, 'saf_document_not_found');
      expect(failure.authority, 'com.android.providers.downloads.documents');
      expect(failure.stage, 'resolve');
    });

    test('tolerates a platform error with no details map', () {
      final failure = AndroidSafFailure.fromPlatformException(
        'readBytesFromUri',
        PlatformException(code: 'saf_io_error', message: 'boom'),
      );

      expect(failure.code, 'saf_io_error');
      expect(failure.message, 'boom');
      expect(failure.authority, isNull);
      expect(failure.stage, isNull);
    });

    test('describes the provider and stage for a crash report', () {
      final failure = AndroidSafFailure.fromPlatformException(
        'readBytesFromTreePath',
        PlatformException(
          code: 'saf_read_failed',
          message: 'FileNotFoundException: no such document',
          details: {'authority': 'com.example.cloud', 'stage': 'open'},
        ),
      );

      final description = failure.toString();
      expect(description, contains('readBytesFromTreePath'));
      expect(description, contains('saf_read_failed'));
      expect(description, contains('stage=open'));
      expect(description, contains('provider=com.example.cloud'));
      expect(description, contains('FileNotFoundException'));
    });

    test('omits absent fields rather than printing null', () {
      const failure = AndroidSafFailure(
        operation: 'readBytesFromUri',
        code: 'saf_io_error',
      );

      expect(failure.toString(), isNot(contains('null')));
      expect(failure.toString(), isNot(contains('stage=')));
      expect(failure.toString(), isNot(contains('provider=')));
    });
  });

  group('AndroidSafService — failure reporting', () {
    test('reports the reason and still returns null for tree reads', () async {
      stubFailure(
        PlatformException(
          code: 'saf_document_not_found',
          message: 'No document matching the requested path exists',
          details: {
            'authority': 'com.android.externalstorage.documents',
            'stage': 'resolve',
          },
        ),
      );

      AndroidSafFailure? reported;
      final bytes = await AndroidSafService.readBytesFromTreePath(
        'content://tree/abc',
        'Volume 1.mokuro',
        onFailure: (failure) => reported = failure,
      );

      // Callers keep their null-means-absent contract; the reason is what is
      // new, so MEKURU-15-style reports say why rather than just "could not
      // read".
      expect(bytes, isNull);
      expect(reported, isNotNull);
      expect(reported!.code, 'saf_document_not_found');
      expect(reported!.stage, 'resolve');
      expect(reported!.authority, 'com.android.externalstorage.documents');
      expect(reported!.operation, 'readBytesFromTreePath');
    });

    test('reports text reads too', () async {
      stubFailure(
        PlatformException(
          code: 'saf_read_failed',
          message: 'SecurityException: permission denied',
          details: {'authority': 'com.example.cloud', 'stage': 'read'},
        ),
      );

      AndroidSafFailure? reported;
      final text = await AndroidSafService.readTextFromTreePath(
        'content://tree/abc',
        'Volume 1.mokuro',
        onFailure: (failure) => reported = failure,
      );

      expect(text, isNull);
      expect(reported!.operation, 'readTextFromTreePath');
      expect(reported!.stage, 'read');
    });

    test('flags a missing method channel distinctly', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw MissingPluginException('no implementation'),
      );

      AndroidSafFailure? reported;
      final bytes = await AndroidSafService.readBytesFromUri(
        'content://doc/1',
        onFailure: (failure) => reported = failure,
      );

      expect(bytes, isNull);
      expect(reported!.code, 'missing_plugin');
    });

    test('leaves callers that ignore the reason unaffected', () async {
      stubFailure(PlatformException(code: 'saf_io_error'));

      expect(
        await AndroidSafService.readBytesFromTreePath(
          'content://tree/abc',
          'Volume 1.mokuro',
        ),
        isNull,
      );
      expect(
        await AndroidSafService.existsInTreePath(
          'content://tree/abc',
          'Volume 1.mokuro',
        ),
        isFalse,
      );
      expect(
        await AndroidSafService.listNamesInTreeDir('content://tree/abc'),
        isEmpty,
      );
    });
  });
}
