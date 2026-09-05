import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../shared/test_database.dart';

void main() {
  tearDown(() {
    usageLogSinkOverride = null;
    usageCountSinkOverride = null;
    usageAnalyticsSinkOverride = null;
  });

  group('fail-safety', () {
    test('logUsage does not propagate sink failures', () {
      usageLogSinkOverride = (message, attributes, {required isWarning}) =>
          throw StateError('sentry down');
      usageAnalyticsSinkOverride = (name, parameters) =>
          throw StateError('firebase down');

      expect(
        () => logUsage('session.summary', attrs: {'pages_turned': 3}),
        returnsNormally,
      );
    });

    test('logFailure does not propagate sink failures', () {
      usageLogSinkOverride = (message, attributes, {required isWarning}) =>
          throw StateError('sentry down');

      expect(
        () => logFailure('ocr.job', Exception('original failure')),
        returnsNormally,
      );
    });

    test('countUsage does not propagate sink failures', () {
      usageCountSinkOverride = (name, value, attributes) =>
          throw StateError('sentry down');

      expect(() => countUsage('reader.page_turn'), returnsNormally);
    });
  });

  group('logUsage', () {
    test('keeps the message constant and converts attributes', () {
      String? loggedMessage;
      Map<String, SentryAttribute>? loggedAttributes;
      bool? loggedIsWarning;
      String? analyticsName;
      Map<String, Object>? analyticsParams;

      usageLogSinkOverride = (message, attributes, {required isWarning}) {
        loggedMessage = message;
        loggedAttributes = attributes;
        loggedIsWarning = isWarning;
      };
      usageAnalyticsSinkOverride = (name, parameters) {
        analyticsName = name;
        analyticsParams = parameters;
      };

      logUsage(
        'reader.settings_changed',
        attrs: {
          'setting': 'furigana_mode',
          'count': 3,
          'enabled': true,
          'ratio': 0.5,
        },
      );

      expect(loggedMessage, 'reader.settings_changed');
      expect(loggedIsWarning, isFalse);
      expect(
        loggedAttributes!.keys,
        containsAll(['setting', 'count', 'enabled', 'ratio']),
      );
      expect(analyticsName, 'reader_settings_changed');
      expect(analyticsParams!['setting'], 'furigana_mode');
      expect(analyticsParams!['count'], 3);
      // Firebase Analytics only accepts String and num values.
      expect(analyticsParams!['enabled'], 1);
      expect(analyticsParams!['ratio'], 0.5);
    });
  });

  group('logFailure', () {
    test('reduces the error to its runtime type and warns', () {
      String? loggedMessage;
      Map<String, SentryAttribute>? loggedAttributes;
      bool? loggedIsWarning;
      usageLogSinkOverride = (message, attributes, {required isWarning}) {
        loggedMessage = message;
        loggedAttributes = attributes;
        loggedIsWarning = isWarning;
      };
      usageAnalyticsSinkOverride = (name, parameters) {};

      logFailure(
        'download.failed',
        StateError('/storage/emulated/0/secret book.epub'),
        attrs: {'asset': 'unidic'},
      );

      expect(loggedMessage, 'download.failed');
      expect(loggedIsWarning, isTrue);
      expect(loggedAttributes, contains('error_type'));
      expect(loggedAttributes, contains('asset'));
      // The error text (which could hold a path) must not reach the sink.
      expect(loggedMessage, isNot(contains('secret')));
    });

    test('attaches a sanitized error_message alongside error_type', () {
      Map<String, SentryAttribute>? loggedAttributes;
      usageLogSinkOverride = (message, attributes, {required isWarning}) {
        loggedAttributes = attributes;
      };
      usageAnalyticsSinkOverride = (name, parameters) {};

      logFailure(
        'book.import_failed',
        StateError('/storage/emulated/0/secret.epub'),
      );

      expect(loggedAttributes!['error_type']?.value, 'StateError');
      final message = loggedAttributes!['error_message']?.value as String?;
      expect(message, isNotNull);
      expect(message, contains('Bad state'));
      expect(message, isNot(contains('secret')));
    });
  });

  group('sanitizeErrorText', () {
    test('redacts absolute POSIX paths', () {
      final out = sanitizeErrorText(
        'Bad state: /storage/emulated/0/secret.epub',
      );
      expect(out, isNot(contains('secret')));
      expect(out, contains('Bad state:'));
    });

    test('redacts SAF pseudo-paths with colons in segments', () {
      final out = sanitizeErrorText(
        "PathNotFoundException: Cannot open file, path = "
        "'/document/primary:Download/MyFolder/manual_backup_2026.mekuru' "
        '(OS Error: No such file or directory, errno = 2)',
      );
      expect(out, isNot(contains('MyFolder')));
      expect(out, isNot(contains('manual_backup')));
      expect(out, contains('Cannot open file'));
      expect(out, contains('No such file'));
    });

    test('redacts Windows paths', () {
      final out = sanitizeErrorText(r'Cannot open C:\Users\matt\diary.txt');
      expect(out, isNot(contains('diary')));
      expect(out, isNot(contains('Users')));
    });

    test('redacts URIs but keeps the HTTP status readable', () {
      final out = sanitizeErrorText(
        'HttpException: Failed to download dictionary: HTTP 403, '
        'uri = https://api.github.com/repos/foo/bar/releases/latest',
      );
      expect(out, isNot(contains('github')));
      expect(out, contains('HTTP 403'));
    });

    test('redacts bare filenames with book-ish extensions', () {
      final out = sanitizeErrorText('Could not parse 秘密の本 volume 1.cbz');
      expect(out, isNot(contains('volume 1')));
      expect(out, contains('Could not parse'));
    });

    test('keeps only the first line so parse snippets stay on-device', () {
      final out = sanitizeErrorText(
        'FormatException: Unexpected character (at character 3)\n'
        '{"data": "secret words from a dictionary"}\n'
        '  ^',
      );
      expect(out, isNot(contains('secret words')));
      expect(out, contains('Unexpected character (at character 3)'));
    });

    test('caps at 100 chars so Firebase Analytics keeps the value intact', () {
      final out = sanitizeErrorText('x${'y' * 500}');
      expect(out.length, lessThanOrEqualTo(100));
    });
  });

  group('emitInstallGauges', () {
    test('counts rows without throwing', () async {
      final db = createTestDatabase();
      addTearDown(() async => db.close());

      await db
          .into(db.books)
          .insert(BooksCompanion.insert(title: 'a', filePath: '/tmp/a.epub'));
      await db
          .into(db.dictionaryMetas)
          .insert(DictionaryMetasCompanion.insert(name: 'enabled dict'));
      await db
          .into(db.dictionaryMetas)
          .insert(
            DictionaryMetasCompanion.insert(
              name: 'disabled dict',
              isEnabled: const Value(false),
            ),
          );
      await db
          .into(db.savedWords)
          .insert(
            SavedWordsCompanion.insert(expression: '言葉', glossaries: '[]'),
          );

      await expectLater(emitInstallGauges(db, isPro: false), completes);
    });
  });

  group('setUsageTag', () {
    tearDown(resetUsageTagsForTest);

    test('tags ride along on every log and count; caller attrs win', () {
      Map<String, SentryAttribute>? logged;
      Map<String, SentryAttribute>? counted;
      usageLogSinkOverride = (message, attributes, {required isWarning}) =>
          logged = attributes;
      usageCountSinkOverride = (name, value, attributes) =>
          counted = attributes;

      setUsageTag('pro', 'true');
      logUsage('reader.book_opened', attrs: {'format': 'epub'});
      countUsage('reader.page_turn', attrs: {'pro': 'override'});

      expect(logged!['pro']!.value, 'true');
      expect(logged!['format']!.value, 'epub');
      expect(counted!['pro']!.value, 'override');
    });

    test('attribute-free metrics stay attribute-free without tags', () {
      Map<String, SentryAttribute>? counted = const {};
      usageCountSinkOverride = (name, value, attributes) =>
          counted = attributes;

      countUsage('reader.page_turn');

      expect(counted, isNull);
    });

    test('librarySizeBucket boundaries', () {
      expect([0, 1, 9, 10, 49, 50, 199, 200, 5000].map(librarySizeBucket), [
        '0',
        '1-9',
        '1-9',
        '10-49',
        '10-49',
        '50-199',
        '50-199',
        '200+',
        '200+',
      ]);
    });
  });
}
