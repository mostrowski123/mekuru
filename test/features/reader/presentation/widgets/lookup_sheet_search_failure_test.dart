import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_query_service.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/features/reader/presentation/widgets/lookup_sheet.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/main.dart' show databaseProvider;
import 'package:sentry_flutter/sentry_flutter.dart' show SentryAttribute;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../shared/test_database.dart';
import '../../../../test_app.dart';

const _word = '秘密';

/// How SQLite reports a broken database: the statement and its parameters,
/// here the looked-up word, follow on a second line.
class _BrokenQueryService extends DictionaryQueryService {
  _BrokenQueryService(super.db);

  @override
  Future<List<DictionaryEntryWithSource>> searchLookupWithSource(
    String primary, [
    String? secondary,
  ]) async => throw Exception(
    'SqliteException(11): database disk image is malformed\n'
    '  Causing statement: SELECT ..., parameters: $primary',
  );

  @override
  Future<Map<String, List<PitchAccentResult>>> searchPitchAccentsBatch(
    Iterable<String> expressions,
  ) async => const {};
}

/// Finds nothing, so the sheet asks which dictionaries can answer.
class _EmptyQueryService extends DictionaryQueryService {
  _EmptyQueryService(super.db);

  @override
  Future<List<DictionaryEntryWithSource>> searchLookupWithSource(
    String primary, [
    String? secondary,
  ]) async => const [];

  @override
  Future<Map<String, List<PitchAccentResult>>> searchPitchAccentsBatch(
    Iterable<String> expressions,
  ) async => const {};
}

/// Its first check of which dictionaries can answer a lookup fails.
class _BrokenCheckRepository extends DictionaryRepository {
  _BrokenCheckRepository(super.db);

  var _failed = false;

  @override
  Future<bool> anyAnswersLookups(List<int> ids) async {
    if (_failed) return super.anyAnswersLookups(ids);
    _failed = true;
    throw Exception('SqliteException(5): database is locked');
  }
}

void main() {
  final ja = lookupAppLocalizations(const Locale('ja'));
  late AppDatabase db;
  final logs = <(String, Map<String, SentryAttribute>)>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = createTestDatabase();
    logs.clear();
    usageLogSinkOverride = (message, attributes, {required isWarning}) =>
        logs.add((message, attributes));
    usageAnalyticsSinkOverride = (_, _) {};
  });

  tearDown(() async {
    usageLogSinkOverride = null;
    usageAnalyticsSinkOverride = null;
    await db.close();
  });

  testWidgets('a search that fails says so in Japanese and is logged once', (
    tester,
  ) async {
    final rebuild = ValueNotifier(0);
    addTearDown(rebuild.dispose);
    final resolved = <bool>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          dictionaryQueryServiceProvider.overrideWithValue(
            _BrokenQueryService(db),
          ),
          dictionariesProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: buildLocalizedTestApp(
          locale: const Locale('ja'),
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: rebuild,
              // Each rebuild hands the sheet a new widget.
              builder: (_, _, _) => SizedBox.expand(
                child: LookupSheet(
                  selectedText: _word,
                  onLookupResolved: resolved.add,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('malformed'), findsNothing);
    expect(find.text(ja.commonSearchFailed), findsOneWidget);
    // The reader still hears that nothing was found.
    expect(resolved, [false]);

    // Built again, not looked up again: still one failure.
    rebuild.value++;
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(ja.commonSearchFailed), findsOneWidget);
    final failures = logs.where((log) => log.$1 == 'lookup.search_failed');
    expect(failures, hasLength(1));
    for (final attribute in failures.single.$2.values) {
      expect('${attribute.value}', isNot(contains(_word)));
    }
  });

  testWidgets('a failed check of which dictionaries can answer also says the '
      'search failed, and the next lookup asks again', (tester) async {
    final jmdict = DictionaryMeta(
      id: 1,
      name: 'JMdict',
      isEnabled: true,
      dateImported: DateTime(2026, 10, 3),
      sortOrder: 0,
      isHidden: false,
    );
    final word = ValueNotifier(_word);
    addTearDown(word.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          dictionaryQueryServiceProvider.overrideWithValue(
            _EmptyQueryService(db),
          ),
          dictionaryRepositoryProvider.overrideWithValue(
            _BrokenCheckRepository(db),
          ),
          dictionariesProvider.overrideWith((ref) => Stream.value([jmdict])),
        ],
        child: buildLocalizedTestApp(
          locale: const Locale('ja'),
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: word,
              builder: (_, text, _) =>
                  SizedBox.expand(child: LookupSheet(selectedText: text)),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(ja.commonSearchFailed), findsOneWidget);
    expect(find.text(ja.dictionaryNoResultsFound), findsNothing);
    expect(logs.where((log) => log.$1 == 'lookup.search_failed'), hasLength(1));

    word.value = '暗号';
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(ja.dictionaryNoResultsFound), findsOneWidget);
    expect(find.text(ja.commonSearchFailed), findsNothing);
  });
}
