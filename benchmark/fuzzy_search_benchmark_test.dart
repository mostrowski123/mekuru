import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_query_service.dart';
import 'package:mekuru/features/dictionary/data/services/lookup_benchmark.dart';

/// Search-screen benchmark: seeds a large in-memory DB shaped like a real
/// multi-dictionary install (kanji words, katakana loanwords, English
/// glossaries, sparse frequency data) and runs [FuzzySearchBenchmark]
/// against [FuzzySearchBenchmark.corpus].
///
/// There is no A/B flag on this path — run this test before and after a
/// change and compare the printed per-query medians. Assertions are kept to
/// behavior that must hold at every commit so the harness itself stays a
/// stable measuring stick.
///
/// Run with: flutter test benchmark/fuzzy_search_benchmark_test.dart

const int _numDictionaries = 10;
const int _entriesPerDictionary = 15000;
const int _vocabPoolSize = 8000;

/// Corpus words seeded with correct readings and English glosses so every
/// query family in [FuzzySearchBenchmark.corpus] has real rows to hit.
const List<(String expression, String reading, String gloss)> _knownWords = [
  ('食べる', 'たべる', 'to eat; to consume'),
  ('食べ物', 'たべもの', 'food'),
  ('走る', 'はしる', 'to run'),
  ('行く', 'いく', 'to go'),
  ('日本語', 'にほんご', 'Japanese language'),
  ('日本', 'にほん', 'Japan'),
  ('学校', 'がっこう', 'school'),
  ('時間', 'じかん', 'time; hour'),
  ('先生', 'せんせい', 'teacher; instructor'),
  ('カード', 'カード', 'card'),
  ('コーヒー', 'コーヒー', 'coffee'),
  ('ケーキ', 'ケーキ', 'cake'),
  ('セーター', 'セーター', 'sweater'),
  ('タクシー', 'タクシー', 'taxi'),
  ('テレビ', 'テレビ', 'television'),
];

/// English word pool for long-tail glossaries. Includes substring traps for
/// the "eat"/"run" queries (theater, beaten, prune, brunch) so the English
/// path is exercised against realistic false-positive volume.
const List<String> _glossWords = [
  'house', 'water', 'mountain', 'river', 'theater', 'beaten', 'prune',
  'brunch', 'weather', 'feather', 'threat', 'created', 'treaty', 'sweater',
  'grunt', 'trunk', 'crunch', 'wheat', 'cheat', 'heater', 'person', 'thing',
  'place', 'moment', 'evening', 'morning', 'window', 'garden', 'bridge',
  'station', 'letter', 'paper', 'stone', 'cloud', 'forest', 'island',
  'valley', 'harbor', 'market', 'temple', 'castle', 'village', 'street',
  'corner', 'silence', 'shadow', 'spring', 'autumn', 'winter', 'summer',
];

class _VocabPool {
  _VocabPool(int seed, int size) : _rng = Random(seed) {
    _surfaces = List.generate(size, (_) => _randomSurface());
    _readings = List.generate(size, (_) => _randomReading());
    _glosses = List.generate(size, (_) => _randomGloss());
  }

  final Random _rng;
  late final List<String> _surfaces;
  late final List<String> _readings;
  late final List<String> _glosses;

  List<String> get surfaces => _surfaces;
  List<String> get readings => _readings;
  List<String> get glosses => _glosses;

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
    final len = 2 + _rng.nextInt(4);
    final buf = StringBuffer();
    for (var i = 0; i < len; i++) {
      buf.write(kana[_rng.nextInt(kana.length)]);
    }
    return buf.toString();
  }

  String _randomGloss() {
    final len = 2 + _rng.nextInt(5);
    final words = List.generate(
      len,
      (_) => _glossWords[_rng.nextInt(_glossWords.length)],
    );
    return words.join(' ');
  }
}

Future<void> _seedLargeDb(DictionaryRepository repo) async {
  final pool = _VocabPool(42, _vocabPoolSize);
  final rng = Random(1337);

  for (var d = 0; d < _numDictionaries; d++) {
    final dictId = await repo.insertDictionary('FuzzyBench-$d', sortOrder: d);

    final entries = <DictionaryEntriesCompanion>[];

    for (final (expression, reading, gloss) in _knownWords) {
      entries.add(DictionaryEntriesCompanion.insert(
        expression: expression,
        reading: Value(reading),
        glossaries: jsonEncode([gloss]),
        dictionaryId: dictId,
      ));
    }

    for (var i = 0; i < _entriesPerDictionary; i++) {
      final idx = rng.nextInt(_vocabPoolSize);
      entries.add(DictionaryEntriesCompanion.insert(
        expression: pool.surfaces[idx],
        reading: Value(pool.readings[idx]),
        glossaries: jsonEncode([pool.glosses[idx]]),
        dictionaryId: dictId,
      ));
    }

    await repo.batchInsertEntries(entries, batchSize: 5000);

    // Frequency data: known words get strong (low) ranks so ranking-sensitive
    // paths behave like a real install; a random slice of the pool gets
    // scattered ranks.
    final freqs = <FrequenciesCompanion>[];
    for (var i = 0; i < _knownWords.length; i++) {
      final (expression, reading, _) = _knownWords[i];
      freqs.add(FrequenciesCompanion.insert(
        expression: expression,
        reading: Value(reading),
        frequencyRank: 100 + i,
        dictionaryId: dictId,
      ));
    }
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

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
  });

  test(
    'fuzzy search benchmark: times the search-screen path at scale',
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
      await _seedLargeDb(repo);
      seedSw.stop();
      debugPrint('[bench] Seed complete in ${seedSw.elapsedMilliseconds} ms');

      // Sanity gates only — behavior that must hold at every commit so this
      // harness stays a stable before/after measuring stick.
      final exact = await service.fuzzySearchWithSource('食べる');
      expect(exact, isNotEmpty);
      expect(exact.first.entry.expression, '食べる');

      final english = await service.fuzzySearchWithSource('eat');
      expect(english, isNotEmpty);

      final report = await FuzzySearchBenchmark(service).run();

      expect(
        report.medianMicrosByQuery.keys,
        containsAll(FuzzySearchBenchmark.corpus),
      );
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

/// Avoid importing foundation.dart just for debugPrint.
void debugPrint(String msg) {
  // ignore: avoid_print
  print(msg);
}
