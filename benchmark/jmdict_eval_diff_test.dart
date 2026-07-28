import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A/B differ for jmdict_eval_test.dart runs. Reads two JSON outputs
/// (default %LOCALAPPDATA%/mekuru_eval/runs/base.json and head.json,
/// override with MEKURU_EVAL_BASE / MEKURU_EVAL_HEAD file paths) and prints
/// rank changes, top-10 churn, flooding signals, and latency deltas.
///
/// The one hard assertion: no regression-sentinel expectation may get worse
/// from base to head. Everything else is reported for human judgment.
///
/// MANUAL HARNESS — not run by CI. This file stays at HEAD only (it is never
/// copied into the A/B worktree, so it may use any current API).
///
/// Run with: flutter test benchmark/jmdict_eval_diff_test.dart -r expanded

void _log(String msg) {
  // ignore: avoid_print
  print(msg);
}

Map<String, dynamic> _load(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    fail(
      'Missing eval run: $path. Run benchmark/jmdict_eval_test.dart with '
      'MEKURU_EVAL_LABEL set (and in the A/B worktree for the base run), or '
      'point MEKURU_EVAL_BASE / MEKURU_EVAL_HEAD at existing JSON files.',
    );
  }
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

String _fmtMs(int micros) => (micros / 1000).toStringAsFixed(1);

void main() {
  test('diff base vs head eval runs', () {
    final env = Platform.environment;
    final root =
        env['MEKURU_EVAL_HOME'] ??
        '${env['LOCALAPPDATA'] ?? Directory.systemTemp.path}'
            '${Platform.pathSeparator}mekuru_eval';
    final base = _load(env['MEKURU_EVAL_BASE'] ?? '$root/runs/base.json');
    final head = _load(env['MEKURU_EVAL_HEAD'] ?? '$root/runs/head.json');

    // Optional noise floor: a second head run under a different label.
    final head2Path = env['MEKURU_EVAL_HEAD2'] ?? '$root/runs/head2.json';

    _log(
      '=== diff base(${base['commit']}) -> head(${head['commit']}) '
      'schema ${base['schema']}/${head['schema']} ===',
    );

    // Preflight: identical DB content or the comparison is meaningless.
    final baseFp = (base['db'] as Map)['fingerprint'];
    final headFp = (head['db'] as Map)['fingerprint'];
    if (baseFp != headFp) {
      fail(
        'DB fingerprints differ — runs used different dictionary content:\n'
        '  base: $baseFp\n  head: $headFp\n'
        'Rebuild/reuse one master DB for both runs.',
      );
    }

    Map<String, Map<String, dynamic>> byId(Map<String, dynamic> run) => {
      for (final q in run['queries'] as List)
        (q as Map<String, dynamic>)['id'] as String: q,
    };
    final baseQ = byId(base);
    final headQ = byId(head);
    final head2Q = File(head2Path).existsSync() ? byId(_load(head2Path)) : null;

    final onlyOneSide = <String>[
      ...baseQ.keys
          .where((id) => !headQ.containsKey(id))
          .map((id) => 'base:$id'),
      ...headQ.keys
          .where((id) => !baseQ.containsKey(id))
          .map((id) => 'head:$id'),
    ];

    // Noise floor from head vs head2 (median micros spread per query).
    var noiseFloorMicros = 0;
    final spreads = <int>[
      if (head2Q != null)
        for (final id in headQ.keys)
          ((headQ[id]!['medianMicros'] as int) -
                  ((head2Q[id]?['medianMicros'] ?? headQ[id]!['medianMicros'])
                      as int))
              .abs(),
    ]..sort();
    if (spreads.isNotEmpty) {
      noiseFloorMicros = spreads.last;
      _log(
        'noise floor (head vs head2): p50 '
        '${_fmtMs(spreads[spreads.length ~/ 2])}ms, '
        'max ${_fmtMs(noiseFloorMicros)}ms',
      );
    } else {
      _log('no head2 run found — latency flags not noise-checked');
    }

    // --- Expectation rank changes ---
    _log('');
    _log('--- expectation rank changes (base -> head) ---');
    final sentinelRegressions = <String>[];
    for (final id in baseQ.keys) {
      final b = baseQ[id]!;
      final h = headQ[id];
      if (h == null) continue;
      final bExp = b['expectations'] as List;
      final hExp = h['expectations'] as List;
      for (var i = 0; i < bExp.length && i < hExp.length; i++) {
        final target = bExp[i]['target'];
        final br = bExp[i]['rank'] as int;
        final hr = hExp[i]['rank'] as int;
        String verdict;
        if (br == hr) {
          verdict = 'SAME';
        } else if (br == -1) {
          verdict = 'NEW';
        } else if (hr == -1) {
          verdict = 'LOST';
        } else if (hr < br) {
          verdict = 'BETTER';
        } else {
          verdict = 'WORSE';
        }
        if (verdict != 'SAME') {
          _log('  $id "$target": $br -> $hr  $verdict');
        }
        final isSentinel = b['category'] == 'sentinel';
        final regressed = verdict == 'LOST' || verdict == 'WORSE';
        // A sentinel that got worse AND now misses its maxRank bound is a
        // hard regression; rank jitter inside the bound is reported only.
        if (isSentinel && regressed && hExp[i]['pass'] == false) {
          sentinelRegressions.add('$id "$target": $br -> $hr');
        }
      }
    }

    // --- Head-side expectation failures (desired behavior not met) ---
    _log('');
    _log('--- head expectation failures ---');
    var headFailures = 0;
    for (final q in headQ.values) {
      for (final e in q['expectations'] as List) {
        if (e['pass'] == false) {
          headFailures++;
          _log(
            '  ${q['id']} "${e['target']}" rank ${e['rank']} '
            '(wanted <= ${e['maxRank']})',
          );
        }
      }
    }
    if (headFailures == 0) _log('  none');

    // --- Top-10 churn + flood signals ---
    _log('');
    _log('--- top-10 churn / flooding ---');
    List<String> tops(Map<String, dynamic> q) => [
      for (final t in q['top'] as List) '${t['expression']}|${t['reading']}',
    ];
    for (final id in baseQ.keys) {
      final b = baseQ[id]!;
      final h = headQ[id];
      if (h == null) continue;
      final bt = tops(b);
      final ht = tops(h);
      final entered = ht.where((e) => !bt.contains(e)).toList();
      final left = bt.where((e) => !ht.contains(e)).toList();
      final floodDelta =
          (h['exactTypedInTop10'] as int) - (b['exactTypedInTop10'] as int);
      final resultDelta = (h['resultCount'] as int) - (b['resultCount'] as int);
      if (entered.isEmpty &&
          left.isEmpty &&
          floodDelta == 0 &&
          resultDelta == 0) {
        continue;
      }
      _log(
        '  $id ("${b['query']}"): typedTop10 ${b['exactTypedInTop10']}'
        '->${h['exactTypedInTop10']}, results ${b['resultCount']}'
        '->${h['resultCount']}',
      );
      if (b['category'] == 'noise') {
        _log('    base top: ${bt.join('  ')}');
        _log('    head top: ${ht.join('  ')}');
      } else {
        if (entered.isNotEmpty) _log('    entered: ${entered.join('  ')}');
        if (left.isNotEmpty) _log('    left:    ${left.join('  ')}');
      }
    }

    // --- Latency ---
    _log('');
    _log('--- latency (flag: >20% AND >5ms AND above noise floor) ---');
    final flagged = <String>[];
    final rows = <(String, int, int)>[];
    for (final id in baseQ.keys) {
      final h = headQ[id];
      if (h == null) continue;
      final bm = baseQ[id]!['medianMicros'] as int;
      final hm = h['medianMicros'] as int;
      rows.add((id, bm, hm));
    }
    rows.sort((a, b) => (b.$3 - b.$2).compareTo(a.$3 - a.$2));
    for (final (id, bm, hm) in rows) {
      final delta = hm - bm;
      final pct = bm == 0 ? 0.0 : delta * 100 / bm;
      final isFlagged = delta > 5000 && pct > 20 && delta > noiseFloorMicros;
      if (isFlagged) flagged.add(id);
      if (delta.abs() > 1000 || isFlagged) {
        _log(
          '  ${id.padRight(22)} ${_fmtMs(bm).padLeft(7)}ms -> '
          '${_fmtMs(hm).padLeft(7)}ms  '
          '(${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(0)}%)'
          '${isFlagged ? '  FLAG' : ''}',
        );
      }
    }
    final ba = base['aggregate'] as Map;
    final ha = head['aggregate'] as Map;
    _log(
      '  aggregate p50 ${_fmtMs(ba['p50'] as int)}ms -> '
      '${_fmtMs(ha['p50'] as int)}ms, p95 ${_fmtMs(ba['p95'] as int)}ms -> '
      '${_fmtMs(ha['p95'] as int)}ms',
    );

    // --- Verdict ---
    _log('');
    _log(
      'verdict: ${sentinelRegressions.isEmpty ? 'NO sentinel regressions' : sentinelRegressions}',
    );
    if (flagged.isNotEmpty) {
      _log('latency flags (informational): $flagged');
    }
    expect(
      sentinelRegressions,
      isEmpty,
      reason: 'regression sentinels got worse from base to head',
    );
    expect(onlyOneSide, isEmpty, reason: 'battery drifted between runs');
  });
}
