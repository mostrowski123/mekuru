import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/services/pii_scrubber.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  group('scrubPaths', () {
    test('replaces app-private data paths', () {
      expect(
        scrubPaths('failed to open /data/user/0/moe.matthew.mekuru/files/x.db'),
        'failed to open <path>',
      );
      expect(
        scrubPaths('cache at /data/data/moe.matthew.mekuru/cache/img.png'),
        'cache at <path>',
      );
    });

    test('replaces shared storage paths including spaces in file names', () {
      expect(
        scrubPaths(
          "FileSystemException: Cannot open file, path = "
          "'/storage/emulated/0/Download/私の本 第1巻.epub' (OS Error: 2)",
        ),
        "FileSystemException: Cannot open file, path = '<path>' (OS Error: 2)",
      );
      expect(
        scrubPaths('reading /sdcard/Books/some title.epub'),
        'reading <path>',
      );
    });

    test('stops at structural delimiters', () {
      expect(
        scrubPaths('/data/user/0/app/files/book.epub: No such file'),
        '<path>: No such file',
      );
    });

    test('leaves pathless text untouched', () {
      const input = 'Dictionary imported with 1234 entries';
      expect(scrubPaths(input), input);
    });
  });

  group('scrubEvent', () {
    test('scrubs exception values, message, and breadcrumbs', () {
      final event = SentryEvent(
        exceptions: [
          SentryException(
            type: 'FileSystemException',
            value: "Cannot open '/storage/emulated/0/book title.epub'",
          ),
        ],
        message: SentryMessage('failed /data/user/0/app/files/x.db'),
        breadcrumbs: [Breadcrumb(message: 'opened /sdcard/foo.epub')],
      );

      final scrubbed = scrubEvent(event, Hint());

      expect(scrubbed.exceptions!.single.value, "Cannot open '<path>'");
      expect(scrubbed.message!.formatted, 'failed <path>');
      expect(scrubbed.breadcrumbs!.single.message, 'opened <path>');
    });

    test('returns event unchanged when there is nothing to scrub', () {
      final event = SentryEvent(message: SentryMessage('plain message'));
      expect(scrubEvent(event, Hint()).message!.formatted, 'plain message');
    });
  });

  group('scrubLog', () {
    test('scrubs the log body', () {
      final log = SentryLog(
        timestamp: DateTime.utc(2026, 1, 1),
        level: SentryLogLevel.info,
        body: 'import failed for /storage/emulated/0/b.epub',
        attributes: {},
      );
      expect(scrubLog(log).body, 'import failed for <path>');
    });
  });
}
