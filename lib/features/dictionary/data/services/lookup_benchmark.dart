import 'package:flutter/foundation.dart';

import 'package:mekuru/features/dictionary/data/services/dictionary_query_service.dart';

/// Debug-only A/B benchmark comparing the legacy and batched lookup paths of
/// [DictionaryQueryService.searchLookupWithSource]. Times each path against a
/// fixed Japanese corpus and prints p50/p95/mean plus per-query deltas.
///
/// Intentionally lives in data/services (not test/) so it can be kicked off
/// from a debug button in the dictionary manager against the real on-device
/// database with all the user's enabled dictionaries.
class LookupBenchmark {
  LookupBenchmark(this._service);

  final DictionaryQueryService _service;

  /// Representative lookup corpus covering kanji, kana, deinflected forms,
  /// compound candidates, and common / rare words. Keep this list stable so
  /// successive runs stay comparable.
  static const List<(String primary, String? secondary)> corpus = [
    ('食べる', null),
    ('食べた', '食べた'),
    ('食べている', '食べている'),
    ('飲む', null),
    ('飲んだ', '飲んだ'),
    ('行く', null),
    ('行った', '行った'),
    ('来る', null),
    ('来た', '来た'),
    ('見る', null),
    ('見ている', '見ている'),
    ('走る', null),
    ('走った', '走った'),
    ('書く', null),
    ('書いた', '書いた'),
    ('読む', null),
    ('読んだ', '読んだ'),
    ('話す', null),
    ('話した', '話した'),
    ('聞く', null),
    ('作る', null),
    ('作った', '作った'),
    ('買う', null),
    ('買った', '買った'),
    ('売る', null),
    ('私', 'わたし'),
    ('あなた', null),
    ('これ', null),
    ('それ', null),
    ('大きい', null),
    ('小さい', null),
    ('高い', null),
    ('安い', null),
    ('新しい', null),
    ('古い', null),
    ('楽しい', null),
    ('難しい', null),
    ('簡単', null),
    ('時間', null),
    ('今日', null),
    ('明日', null),
    ('昨日', null),
    ('日本語', null),
    ('英語', null),
    ('学校', null),
    ('先生', null),
    ('学生', null),
    ('友達', null),
    ('家族', null),
    ('仕事', null),
  ];

  /// Run the benchmark and return the full report. Also prints via
  /// [debugPrint] so it shows up in the device log.
  Future<BenchmarkReport> run({int warmupRuns = 2}) async {
    final legacy = await _measure(
      batched: false,
      warmupRuns: warmupRuns,
      label: 'legacy',
    );
    final batched = await _measure(
      batched: true,
      warmupRuns: warmupRuns,
      label: 'batched',
    );

    final report = BenchmarkReport._(legacy: legacy, batched: batched);
    debugPrint(report.summary());
    return report;
  }

  Future<_PathTimings> _measure({
    required bool batched,
    required int warmupRuns,
    required String label,
  }) async {
    final previous = kUseBatchedDictionaryLookup;
    kUseBatchedDictionaryLookup = batched;
    _service.invalidateMetasCache();

    final durationsMicros = <int>[];
    final stopwatch = Stopwatch();

    try {
      // Warmup — pay query-plan and cache costs before measuring.
      for (var i = 0; i < warmupRuns; i++) {
        for (final q in corpus) {
          await _service.searchLookupWithSource(q.$1, q.$2);
        }
      }

      for (final q in corpus) {
        stopwatch
          ..reset()
          ..start();
        await _service.searchLookupWithSource(q.$1, q.$2);
        stopwatch.stop();
        durationsMicros.add(stopwatch.elapsedMicroseconds);
      }
    } finally {
      kUseBatchedDictionaryLookup = previous;
      _service.invalidateMetasCache();
    }

    return _PathTimings(label: label, durationsMicros: durationsMicros);
  }
}

class _PathTimings {
  _PathTimings({required this.label, required this.durationsMicros}) {
    final sorted = [...durationsMicros]..sort();
    p50 = sorted.isEmpty
        ? 0
        : sorted[(sorted.length * 0.5).floor().clamp(0, sorted.length - 1)];
    p95 = sorted.isEmpty
        ? 0
        : sorted[(sorted.length * 0.95).floor().clamp(0, sorted.length - 1)];
    mean = durationsMicros.isEmpty
        ? 0
        : durationsMicros.reduce((a, b) => a + b) / durationsMicros.length;
    total = durationsMicros.fold<int>(0, (a, b) => a + b);
  }

  final String label;
  final List<int> durationsMicros;
  late final int p50;
  late final int p95;
  late final double mean;
  late final int total;
}

/// Side-by-side benchmark summary for legacy and batched lookup paths.
class BenchmarkReport {
  BenchmarkReport._({
    required _PathTimings legacy,
    required _PathTimings batched,
  })  : _legacy = legacy,
        _batched = batched;

  final _PathTimings _legacy;
  final _PathTimings _batched;

  int get samples => _legacy.durationsMicros.length;

  int get legacyP50 => _legacy.p50;
  int get legacyP95 => _legacy.p95;
  double get legacyMean => _legacy.mean;

  int get batchedP50 => _batched.p50;
  int get batchedP95 => _batched.p95;
  double get batchedMean => _batched.mean;

  double get speedupP50 =>
      _batched.p50 == 0 ? 0 : _legacy.p50 / _batched.p50;
  double get speedupP95 =>
      _batched.p95 == 0 ? 0 : _legacy.p95 / _batched.p95;

  String summary() {
    String fmtMicros(num micros) =>
        '${(micros / 1000).toStringAsFixed(2)} ms';
    return [
      '[LookupBenchmark] n=$samples',
      'legacy   p50=${fmtMicros(_legacy.p50)}  p95=${fmtMicros(_legacy.p95)}  '
          'mean=${fmtMicros(_legacy.mean)}',
      'batched  p50=${fmtMicros(_batched.p50)}  p95=${fmtMicros(_batched.p95)}  '
          'mean=${fmtMicros(_batched.mean)}',
      'speedup  p50=${speedupP50.toStringAsFixed(2)}x  '
          'p95=${speedupP95.toStringAsFixed(2)}x',
    ].join('\n');
  }
}
