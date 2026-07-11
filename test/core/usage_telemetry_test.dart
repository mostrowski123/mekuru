import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

AppDatabase createTestDatabase() => AppDatabase(NativeDatabase.memory());

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
}
