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

    test('replaces SAF pseudo-paths with colons in segments', () {
      final out = scrubPaths(
        "Cannot open file, path = "
        "'/document/primary:Download/MyFolder/backup_2026.mekuru' "
        '(OS Error: 2)',
      );
      expect(out, isNot(contains('MyFolder')));
      expect(out, contains('Cannot open file'));
      expect(out, contains('(OS Error: 2)'));
    });

    test('replaces Windows paths', () {
      final out = scrubPaths(r'Cannot open C:\Users\matt\diary.txt');
      expect(out, isNot(contains('diary')));
      expect(out, isNot(contains('Users')));
    });

    test('replaces URIs but keeps surrounding prose', () {
      final out = scrubPaths(
        'HTTP 403, uri = https://api.github.com/repos/foo/bar',
      );
      expect(out, isNot(contains('github')));
      expect(out, contains('HTTP 403'));
    });

    test('replaces bare filenames with book-ish extensions', () {
      final out = scrubPaths('Could not parse 秘密の本 volume 1.cbz');
      expect(out, isNot(contains('volume 1')));
      expect(out, contains('Could not parse'));
    });

    test('replaces bare filenames of the files a manga import reads', () {
      for (final name in [
        'Clinic Notes.html',
        'Clinic Notes.mobile.html',
        'Clinic Notes.bmp',
        'Clinic Notes.tif',
        'Clinic Notes.tiff',
      ]) {
        expect(
          scrubPaths('Not found: $name'),
          isNot(contains('Clinic')),
          reason: name,
        );
      }
    });
  });

  group('scrubPaths on paths as devices and test hosts write them', () {
    const iosBooks =
        '/var/mobile/Containers/Data/Application/'
        '0E984725-C51C-4BF4-9960-E1C80E27ABA0/Documents/books';

    // Each input names a folder or file; the output keeps none of it.
    final cases = <String, String>{
      "PathNotFoundException: Cannot open file, path = '/data/user/0/"
              "moe.matthew.mekuru/app_flutter/books/進撃の巨人 01/page 1.jpg' "
              '(OS Error: No such file or directory, errno = 2)':
          "PathNotFoundException: Cannot open file, path = '<path>' "
          '(OS Error: No such file or directory, errno = 2)',
      'Import failed: /storage/emulated/0/Download/本 棚/a.epub':
          'Import failed: <path>',
      "Cannot open file, path = '/storage/emulated/0/Download/"
              "Kiki's Delivery Service Vol 1.epub' (OS Error: 2)":
          "Cannot open file, path = '<path>' (OS Error: 2)",
      'Permission denied: content://com.android.externalstorage.documents/'
              'tree/${Uri.encodeComponent('primary:Download/本 棚')}/document/'
              '${Uri.encodeComponent('primary:Download/本 棚/a.epub')}':
          'Permission denied: <uri>',
      "PathNotFoundException: Cannot open file, path = '$iosBooks/"
              "進撃の巨人 01/page 1.jpg' "
              '(OS Error: No such file or directory, errno = 2)':
          "PathNotFoundException: Cannot open file, path = '<path>' "
          '(OS Error: No such file or directory, errno = 2)',
      'Opening /private$iosBooks/進撃の巨人 01/page 1.jpg': 'Opening <path>',
      'Load failed: '
              '${Uri.file('/private$iosBooks/進撃の巨人 01/page 1.jpg', windows: false)}':
          'Load failed: <uri>',
      r"PathNotFoundException: Cannot open file, path = 'C:\Users\runneradmin"
              r'\AppData\Local\Temp\mekuru_test_8f2a\books\進撃の巨人 01\page 1.jpg'
              "' (OS Error: The system cannot find the path specified., "
              'errno = 3)':
          "PathNotFoundException: Cannot open file, path = '<path>' "
          '(OS Error: The system cannot find the path specified., errno = 3)',
      r'Cannot open C:\Users\me\AppData\Local\Temp\abc/books/進撃の巨人 01/page 1.jpg':
          'Cannot open <path>',
    };

    for (final MapEntry(key: input, value: scrubbed) in cases.entries) {
      test(input, () => expect(scrubPaths(input), scrubbed));
    }

    test('leaves text that names no file unchanged', () {
      for (final input in [
        "SocketException: Failed host lookup: 'komga.example.com' "
            '(OS Error: No address associated with hostname, errno = 7)',
        '#0      MangaReaderScreen.build (package:mekuru/features/manga/'
            'presentation/screens/manga_reader_screen.dart:12:3)',
        '[Reader] Opened 進撃の巨人 01 at page 12',
      ]) {
        expect(scrubPaths(input), input);
      }
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

    test('leaves sentry.-prefixed SDK attributes untouched', () {
      final log = SentryLog(
        timestamp: DateTime.utc(2026, 1, 1),
        level: SentryLogLevel.warn,
        body: 'download.failed',
        attributes: {
          'sentry.release': SentryAttribute.string(
            'moe.matthew.mekuru@1.28.0+2026030810',
          ),
          'sentry.environment': SentryAttribute.string('play-store'),
          // Not metadata: `sentry.message.*` carries caller-supplied content
          // (populated by the SDK's templated logger API) and must stay
          // scrubbed even though it sits in the `sentry.` namespace.
          'sentry.message.template': SentryAttribute.string(
            'opened /storage/emulated/0/secret.epub',
          ),
          'error_message': SentryAttribute.string(
            'Cannot open /storage/emulated/0/secret.epub',
          ),
        },
      );

      final scrubbed = scrubLog(log);

      expect(
        scrubbed.attributes['sentry.release']?.value,
        'moe.matthew.mekuru@1.28.0+2026030810',
      );
      expect(scrubbed.attributes['sentry.environment']?.value, 'play-store');
      expect(
        scrubbed.attributes['sentry.message.template']?.value,
        isNot(contains('secret')),
      );
      expect(
        scrubbed.attributes['error_message']?.value,
        isNot(contains('secret')),
      );
    });

    test('scrubs string attributes so no attr can leak a path', () {
      final log = SentryLog(
        timestamp: DateTime.utc(2026, 1, 1),
        level: SentryLogLevel.warn,
        body: 'book.import_failed',
        attributes: {
          'error_message': SentryAttribute.string(
            'Cannot open /storage/emulated/0/secret.epub',
          ),
          'count': SentryAttribute.int(3),
        },
      );

      final scrubbed = scrubLog(log);

      expect(
        scrubbed.attributes['error_message']?.value,
        isNot(contains('secret')),
      );
      expect(scrubbed.attributes['count']?.value, 3);
    });
  });
}
