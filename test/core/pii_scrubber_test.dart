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
        'SocketException: Connection refused '
            '(OS Error: Connection refused, errno = 111)',
        '#0      MangaReaderScreen.build (package:mekuru/features/manga/'
            'presentation/screens/manga_reader_screen.dart:12:3)',
        '[Reader] Opened 進撃の巨人 01 at page 12',
      ]) {
        expect(scrubPaths(input), input);
      }
    });
  });

  group('scrubPaths on the server a socket error names', () {
    // A user's own Komga, Kavita or OCR server. An error that wraps the
    // system's text (the OCR client's "Network error: …") carries it too.
    const cases = {
      "SocketException: Failed host lookup: 'komga.example.com' "
              '(OS Error: No address associated with hostname, errno = 7)':
          "SocketException: Failed host lookup: '<host>' "
          '(OS Error: No address associated with hostname, errno = 7)',
      "OcrServerException(0): Network error: Failed host lookup: 'ocr.home'":
          "OcrServerException(0): Network error: Failed host lookup: '<host>'",
      'SocketException: Connection refused (OS Error: Connection refused, '
              'errno = 111), address = 192.168.1.20, port = 50432':
          'SocketException: Connection refused (OS Error: Connection refused, '
          'errno = 111), address = <host>, port = 50432',
      'ClientException with SocketException: Connection timed out '
              '(OS Error: Connection timed out, errno = 110), '
              'address = komga.example.com, port = 44321, '
              'uri=https://komga.example.com/api/v1/books':
          'ClientException with SocketException: Connection timed out '
          '(OS Error: Connection timed out, errno = 110), '
          'address = <host>, port = 44321, uri=<uri>',
    };

    for (final MapEntry(key: input, value: scrubbed) in cases.entries) {
      test(input, () => expect(scrubPaths(input), scrubbed));
    }
  });

  group('scrubPaths on a path that follows any character', () {
    const name = ['Manga', 'Secret', 'Title', 'Here'];
    const android = '/storage/emulated/0/Manga/Secret Title Here/001.jpg';
    const ios =
        '/var/mobile/Containers/Data/Application/ABC/Documents/Manga/'
        'Secret Title Here/001.jpg';

    void expectScrubbed(String input, String prose) {
      final out = scrubPaths(input);
      for (final word in name) {
        expect(out, isNot(contains(word)), reason: input);
      }
      expect(out, contains(prose), reason: input);
    }

    test('in braces, as a Set or Map prints it', () {
      expectScrubbed('Bad state: {$android}', 'Bad state: {');
      expectScrubbed('Bad state: {$ios}', 'Bad state: {');
      expect(
        scrubPaths(
          '{/data/user/0/moe.matthew.mekuru/files/books/'
          'Alpha Beta Gamma Delta/x.epub: 3}',
        ),
        '{<path>: 3}',
      );
    });

    test('after punctuation, arrows and Japanese brackets', () {
      for (final before in ['|', ',', '>', '@', '-', '→', '「']) {
        expectScrubbed('a$before$android', 'a$before');
        expectScrubbed('a$before$ios', 'a$before');
      }
    });

    test("after a letter, under Android's roots", () {
      expectScrubbed('a$android', 'a');
      expectScrubbed(
        'x/data/user/0/moe.matthew.mekuru/files/Manga/Secret Title Here.epub',
        'x',
      );
    });

    test('with angle brackets in a name', () {
      expect(
        scrubPaths(
          "PathNotFoundException: Cannot open file, path = '/var/mobile/"
          'Containers/Data/Application/ABC/Library/Application Support/books/'
          "book_1/<Secret> Title.epub' (OS Error: No such file or directory, "
          'errno = 2)',
        ),
        "PathNotFoundException: Cannot open file, path = '<path>' "
        '(OS Error: No such file or directory, errno = 2)',
      );
      expect(
        scrubPaths('Import failed: /storage/emulated/0/a>b Secret/001.jpg'),
        'Import failed: <path>',
      );
    });

    test('shaped like a stack frame but naming no Dart file', () {
      for (final input in [
        'package:Secret/Title Here',
        'dart:Secret/Title Here',
        'package:secret/Title Here',
      ]) {
        final out = scrubPaths(input);
        expect(out, isNot(contains('Secret')), reason: input);
        expect(out, isNot(contains('secret')), reason: input);
        expect(out, isNot(contains('Title')), reason: input);
      }
      // Real frames stay readable.
      for (final frame in [
        '#1      _rootRunUnary (dart:async/zone.dart:1525:47)',
        '#2      Object.noSuchMethod '
            '(dart:core-patch/object_patch.dart:38:5)',
        '#3      Element.rebuild '
            '(package:flutter/src/widgets/framework.dart:5541:22)',
      ]) {
        expect(scrubPaths(frame), frame);
      }
    });
  });

  group('scrubPaths on long runs of text', () {
    test('a Japanese paragraph with no path takes linear time', () {
      final text = 'あいうえおかきくけこ' * 2000;
      final watch = Stopwatch()..start();
      final scrubbed = scrubPaths(text);
      watch.stop();
      expect(scrubbed, text);
      expect(
        watch.elapsedMilliseconds,
        lessThan(500),
        reason: 'Sentry scrubs on the UI isolate',
      );
    });

    test('a path right after a kept stack frame', () {
      expect(
        scrubPaths('#0 main (package:mekuru/main.dart/秘密/本.epub)'),
        '#0 main (package:mekuru/main.dart<path>)',
      );
    });

    test('a file name right after another one', () {
      expect(scrubPaths('w1 w2 a.epub-x y.zip'), '<file><file>');
    });

    test('a SAF document ID inside Japanese text', () {
      expect(scrubPaths('これはprimary:Download/秘密/本.epubです'), '<path>');
    });
  });

  group('scrubPaths on iOS file errors, which name a file in quotes', () {
    // Foundation's NSCocoaErrorDomain messages, as `localizedDescription`
    // hands them to a PlatformException: the file or folder name in quotes,
    // no path and often no extension. English and Japanese system languages,
    // straight quotes, and German and French.
    final cases = <String, String>{
      'PlatformException(exclude_failed, The file “進撃の巨人 01” '
              'couldn’t be opened because there is no such file., null, null)':
          'PlatformException(exclude_failed, The file “<file>” '
          'couldn’t be opened because there is no such file., null, null)',
      'The file “Clinic Notes” couldn’t be opened because you don’t '
              'have permission to view it.':
          'The file “<file>” couldn’t be opened because you don’t '
          'have permission to view it.',
      'The file “Sample Vol 01” couldn’t be opened because it isn’t '
              'in the correct format.':
          'The file “<file>” couldn’t be opened because it isn’t '
          'in the correct format.',
      '“My Book.epub” couldn’t be moved to “books” because an item '
              'with the same name already exists.':
          '“<file>” couldn’t be moved to “<file>” because an item '
          'with the same name already exists.',
      'You don’t have permission to save the file “Sample Vol 01” in '
              'the folder “Tax Return 2025”.':
          'You don’t have permission to save the file “<file>” in '
          'the folder “<file>”.',
      'The folder “Doctor Letters” doesn’t exist.':
          'The folder “<file>” doesn’t exist.',
      'The file "進撃の巨人 01" couldn\'t be opened because there is no such '
              'file.':
          'The file "<file>" couldn\'t be opened because there is no such '
          'file.',
      '"My Book.epub" couldn\'t be moved to "Manga" because an item with the '
              'same name already exists.':
          '"<file>" couldn\'t be moved to "<file>" because an item with the '
          'same name already exists.',
      'ファイル“進撃の巨人 01”は存在しないため開けませんでした。': 'ファイル“<file>”は存在しないため開けませんでした。',
      'ファイル“My Book.epub”を開けませんでした。': 'ファイル“<file>”を開けませんでした。',
      '“進撃の巨人 01”を“本棚”に移動できませんでした。': '“<file>”を“<file>”に移動できませんでした。',
      'ファイル"進撃の巨人 01"を開けませんでした。': 'ファイル"<file>"を開けませんでした。',
      'Die Datei „Sample Vol 01“ konnte nicht geöffnet werden.':
          'Die Datei „<file>“ konnte nicht geöffnet werden.',
      'Le fichier « Sample Vol 01 » n’a pas pu être ouvert.':
          'Le fichier «<file>» n’a pas pu être ouvert.',
    };

    for (final MapEntry(key: input, value: scrubbed) in cases.entries) {
      test(input, () => expect(scrubPaths(input), scrubbed));
    }

    test('keeps what the app itself quotes readable', () {
      for (final input in [
        // BackupFormatException names the JSON field that failed.
        'Not a valid Mekuru backup file: missing or invalid "version" field',
        'Not a valid Mekuru backup file: invalid "savedWords" field',
        'The operation couldn’t be completed. (NSCocoaErrorDomain error 4.)',
      ]) {
        expect(scrubPaths(input), input);
      }
      // A book's title in a debugPrint breadcrumb goes; the line stays.
      expect(
        scrubPaths('[MokuroParser] Parsed "Sample Vol 01" — 12 pages'),
        '[MokuroParser] Parsed "<file>" — 12 pages',
      );
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
