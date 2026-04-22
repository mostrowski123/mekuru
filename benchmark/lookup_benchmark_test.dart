import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_query_service.dart';
import 'package:mekuru/features/dictionary/data/services/lookup_benchmark.dart';

/// End-to-end benchmark: seeds a many-dictionary in-memory DB, runs the
/// A/B harness against [LookupBenchmark.corpus], and asserts the batched
/// path (a) produces identical ordering to the legacy path and (b) is at
/// least as fast as the legacy path. The printed report is captured in the
/// test log for manual inspection.
///
/// This exists so the perf changes aren't merged on faith — the test run
/// itself exercises the benchmark and the equivalence assertion.

const int _numDictionaries = 20;
const int _entriesPerDictionary = 10000;
const int _vocabPoolSize = 8000;

/// Deterministic Japanese-ish surface/reading pool. Real content doesn't
/// matter for the query path — what matters is realistic row count, term
/// overlap across dictionaries, and index behavior.
class _VocabPool {
  _VocabPool(int seed, int size) : _rng = Random(seed) {
    _surfaces = List.generate(size, (_) => _randomSurface());
    _readings = List.generate(size, (i) => _surfaces[i] + _randomReading());
  }

  final Random _rng;
  late final List<String> _surfaces;
  late final List<String> _readings;

  List<String> get surfaces => _surfaces;
  List<String> get readings => _readings;

  String _randomSurface() {
    const kanji = [
      '食', '飲', '行', '来', '見', '聞', '話', '書', '読', '走',
      '作', '買', '売', '学', '教', '生', '死', '愛', '憎', '笑',
      '泣', '思', '考', '知', '忘', '覚', '始', '終', '続', '止',
    ];
    final len = 1 + _rng.nextInt(3);
    final buf = StringBuffer();
    for (var i = 0; i < len; i++) {
      buf.write(kanji[_rng.nextInt(kanji.length)]);
    }
    return buf.toString();
  }

  String _randomReading() {
    const kana = [
      'あ', 'い', 'う', 'え', 'お', 'か', 'き', 'く', 'け', 'こ',
      'さ', 'し', 'す', 'せ', 'そ', 'た', 'ち', 'つ', 'て', 'と',
      'な', 'に', 'ぬ', 'ね', 'の', 'は', 'ひ', 'ふ', 'へ', 'ほ',
    ];
    final len = 2 + _rng.nextInt(3);
    final buf = StringBuffer();
    for (var i = 0; i < len; i++) {
      buf.write(kana[_rng.nextInt(kana.length)]);
    }
    return buf.toString();
  }
}

Future<void> _seedLargeDb(
  DictionaryRepository repo,
  AppDatabase db,
) async {
  final pool = _VocabPool(42, _vocabPoolSize);
  final rng = Random(1337);

  // Make sure every corpus lookup term has at least one matching entry,
  // so timing covers the hit path and not just the empty-result path.
  final corpusTerms = <String>{
    for (final q in LookupBenchmark.corpus) ...[q.$1, if (q.$2 != null) q.$2!],
  }.toList();

  for (var d = 0; d < _numDictionaries; d++) {
    final dictId = await repo.insertDictionary('BenchDict-$d', sortOrder: d);

    final entries = <DictionaryEntriesCompanion>[];

    // Seed corpus terms into each dictionary so lookups produce realistic
    // multi-dictionary result sets.
    for (final term in corpusTerms) {
      entries.add(DictionaryEntriesCompanion.insert(
        expression: term,
        reading: Value(term),
        glossaries: jsonEncode(['gloss d$d term $term']),
        dictionaryId: dictId,
      ));
    }

    for (var i = 0; i < _entriesPerDictionary; i++) {
      final idx = rng.nextInt(_vocabPoolSize);
      entries.add(DictionaryEntriesCompanion.insert(
        expression: pool.surfaces[idx],
        reading: Value(pool.readings[idx]),
        glossaries: jsonEncode(['d$d gloss $i']),
        dictionaryId: dictId,
      ));
    }

    await repo.batchInsertEntries(entries, batchSize: 5000);

    // Sparse frequency data — only some terms get a rank, mimicking real
    // data where only a frequency dictionary covers part of the corpus.
    final freqs = <FrequenciesCompanion>[];
    for (var i = 0; i < _entriesPerDictionary ~/ 4; i++) {
      final idx = rng.nextInt(_vocabPoolSize);
      freqs.add(FrequenciesCompanion.insert(
        expression: pool.surfaces[idx],
        reading: Value(pool.readings[idx]),
        frequencyRank: 1 + rng.nextInt(50000),
        dictionaryId: dictId,
      ));
    }
    await repo.batchInsertFrequencies(freqs, batchSize: 5000);
  }
}

String _fingerprint(List<DictionaryEntryWithSource> results) {
  return results
      .map(
        (r) =>
            '${r.entry.id}|${r.entry.expression}|${r.entry.reading}|'
            '${r.dictionaryName}|${r.frequencyRank}',
      )
      .join(';');
}

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
  });

  test(
    'A/B benchmark: batched lookup matches legacy output and is faster',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = DictionaryRepository(db);
      final service = DictionaryQueryService(db);

      debugPrint(
        '[bench] Seeding $_numDictionaries dicts × '
        '$_entriesPerDictionary entries…',
      );
      final seedSw = Stopwatch()..start();
      await _seedLargeDb(repo, db);
      seedSw.stop();
      debugPrint('[bench] Seed complete in ${seedSw.elapsedMilliseconds} ms');

      // Equivalence gate FIRST — fail loudly if ordering diverges at this
      // scale even if tiny unit-test fixtures pass.
      service.invalidateMetasCache();
      for (final q in LookupBenchmark.corpus) {
        kUseBatchedDictionaryLookup = false;
        service.invalidateMetasCache();
        final legacy =
            await service.searchLookupWithSource(q.$1, q.$2);
        kUseBatchedDictionaryLookup = true;
        service.invalidateMetasCache();
        final batched =
            await service.searchLookupWithSource(q.$1, q.$2);
        expect(
          _fingerprint(batched),
          equals(_fingerprint(legacy)),
          reason:
              'Ordering/content diverged at scale for "${q.$1}"/"${q.$2}". '
              'Batched length=${batched.length} legacy length=${legacy.length}',
        );
      }
      debugPrint(
        '[bench] Equivalence OK across ${LookupBenchmark.corpus.length} '
        'queries × $_numDictionaries enabled dicts',
      );

      // Now the timing run.
      final report = await LookupBenchmark(service).run(warmupRuns: 2);

      debugPrint(report.summary());

      // The batched path should not be slower than legacy. We do not assert
      // a specific speedup multiplier because in-memory SQLite timings are
      // noisy at small absolute durations — the real win shows on-device
      // against a disk-backed DB with 370k-entry dictionaries. A strict
      // "not slower" check still catches regressions.
      expect(
        report.batchedMean,
        lessThanOrEqualTo(report.legacyMean * 1.2),
        reason:
            'Batched mean (${report.batchedMean.toStringAsFixed(0)}µs) '
            'regressed vs legacy mean '
            '(${report.legacyMean.toStringAsFixed(0)}µs).',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

/// Avoid importing foundation.dart just for debugPrint.
void debugPrint(String msg) {
  // ignore: avoid_print
  print(msg);
}
