import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_importer.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_query_service.dart';
import 'package:mekuru/features/dictionary/data/services/glossary_parser.dart';
import 'package:mekuru/features/dictionary/data/services/romaji_converter.dart';

/// Real-data search evaluation: runs a fixed query battery against the actual
/// JMdict release the app downloads (plus the JPDB frequency dictionary,
/// imported disabled+hidden exactly like the in-app starter pack) and writes
/// per-query quality/latency facts to a JSON file for A/B diffing.
///
/// MANUAL HARNESS — not run by CI (bare `flutter test` only runs test/).
/// First run downloads ~60 MB and imports ~200k entries (several minutes);
/// later runs reuse the cached DB.
///
/// Cache layout (override root with MEKURU_EVAL_HOME, default
/// %LOCALAPPDATA%/mekuru_eval):
///   cache/  downloaded zips + JMdict release tag
///   db/     eval_jmdict.sqlite master (treated read-only after build)
///   runs/   <label>.json outputs + per-run working DB copies
///
/// Env knobs: MEKURU_EVAL_LABEL (default "head"), MEKURU_EVAL_JMDICT_TAG
/// (pin a release, skips the GitHub API), MEKURU_EVAL_OFFLINE=1 (never
/// download), MEKURU_EVAL_REPS / MEKURU_EVAL_WARMUPS, MEKURU_EVAL_TOP,
/// MEKURU_EVAL_REBUILD_DB=1.
///
/// IMPORTANT: this file is copied verbatim into a worktree at the commit
/// UNDER COMPARISON when A/B testing — it must only use API that exists on
/// both sides (fuzzySearchWithSource, RomajiConverter.isRomaji / convert /
/// katakanaToHiragana / hiraganaToKatakana, importer, repository). Do not
/// reference newly added API here. Expectations describe DESIRED behavior
/// and are never branched per commit: a "fail" on the old side is exactly
/// the signal the differ (jmdict_eval_diff_test.dart) turns into "NEW".
///
/// Run with: flutter test benchmark/jmdict_eval_test.dart -r expanded

void _log(String msg) {
  // ignore: avoid_print
  print(msg);
}

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

class _Config {
  _Config(Map<String, String> env)
    : home = Directory(
        env['MEKURU_EVAL_HOME'] ??
            '${env['LOCALAPPDATA'] ?? Directory.systemTemp.path}'
                '${Platform.pathSeparator}mekuru_eval',
      ),
      label = env['MEKURU_EVAL_LABEL'] ?? 'head',
      pinnedTag = env['MEKURU_EVAL_JMDICT_TAG'],
      offline = env['MEKURU_EVAL_OFFLINE'] == '1',
      rebuildDb = env['MEKURU_EVAL_REBUILD_DB'] == '1',
      reps = int.tryParse(env['MEKURU_EVAL_REPS'] ?? '') ?? 5,
      warmups = int.tryParse(env['MEKURU_EVAL_WARMUPS'] ?? '') ?? 1,
      topN = int.tryParse(env['MEKURU_EVAL_TOP'] ?? '') ?? 10;

  final Directory home;
  final String label;
  final String? pinnedTag;
  final bool offline;
  final bool rebuildDb;
  final int reps;
  final int warmups;
  final int topN;

  Directory get cacheDir => Directory('${home.path}/cache');
  Directory get dbDir => Directory('${home.path}/db');
  Directory get runsDir => Directory('${home.path}/runs');
  File get masterDb => File('${dbDir.path}/eval_jmdict.sqlite');
  File get buildingDb => File('${dbDir.path}/eval_jmdict.building.sqlite');
  File get jmdictZip => File('${cacheDir.path}/JMdict_english.zip');
  File get jmdictTagFile => File('${cacheDir.path}/JMdict_english.tag');
  File get jpdbZip =>
      File('${cacheDir.path}/JPDB_v2.2_Frequency_Kana_2024-10-13.zip');
}

const _jpdbUrl =
    'https://github.com/Kuuuube/yomitan-dictionaries/raw/main/'
    'dictionaries/JPDB_v2.2_Frequency_Kana_2024-10-13.zip';
const _jpdbDictName = 'JPDBv2㋕';

// ---------------------------------------------------------------------------
// Query battery
// ---------------------------------------------------------------------------

enum EvalCategory { sentinel, newFeature, noise, pathological }

/// A word we hope to see in the results. Matches a result card when the
/// card's expression OR reading equals [target] (robust to how a given
/// JMdict release splits kanji/kana variants). [maxRank] null = record the
/// rank but never judge it (content-drift-prone cases).
class Expect {
  const Expect(this.target, {this.maxRank});

  final String target;
  final int? maxRank;
}

class EvalQuery {
  const EvalQuery(
    this.id,
    this.query,
    this.category, {
    this.expect = const [],
    this.note = '',
  });

  final String id;
  final String query;
  final EvalCategory category;
  final List<Expect> expect;
  final String note;
}

const List<EvalQuery> _battery = [
  // --- Regression sentinels: paths the change must not have touched. ---
  EvalQuery(
    'sen.kanji.taberu',
    '食べる',
    EvalCategory.sentinel,
    expect: [Expect('食べる', maxRank: 0)],
  ),
  EvalQuery(
    'sen.kanji.nihongo',
    '日本語',
    EvalCategory.sentinel,
    expect: [Expect('日本語', maxRank: 0)],
  ),
  EvalQuery(
    'sen.kanji.gakkou',
    '学校',
    EvalCategory.sentinel,
    expect: [Expect('学校', maxRank: 0)],
  ),
  EvalQuery(
    'sen.kanji.jikan',
    '時間',
    EvalCategory.sentinel,
    expect: [Expect('時間', maxRank: 0)],
  ),
  EvalQuery(
    'sen.kanji.watashi',
    '私',
    EvalCategory.sentinel,
    expect: [Expect('私', maxRank: 0)],
  ),
  EvalQuery(
    'sen.kanji.benkyou',
    '勉強',
    EvalCategory.sentinel,
    expect: [Expect('勉強', maxRank: 0)],
  ),
  EvalQuery(
    'sen.deinf.tabeta',
    '食べた',
    EvalCategory.sentinel,
    expect: [Expect('食べる', maxRank: 3)],
  ),
  EvalQuery(
    'sen.deinf.itta',
    '行った',
    EvalCategory.sentinel,
    expect: [Expect('行く', maxRank: 5)],
  ),
  EvalQuery(
    'sen.kana.taberu',
    'たべる',
    EvalCategory.sentinel,
    expect: [Expect('食べる', maxRank: 3)],
  ),
  EvalQuery(
    'sen.kana.nihongo',
    'にほんご',
    EvalCategory.sentinel,
    expect: [Expect('日本語', maxRank: 3)],
  ),
  EvalQuery(
    'sen.kata.card',
    'カード',
    EvalCategory.sentinel,
    expect: [Expect('カード', maxRank: 3)],
  ),
  EvalQuery(
    'sen.kata.coffee',
    'コーヒー',
    EvalCategory.sentinel,
    expect: [Expect('コーヒー', maxRank: 3)],
  ),
  EvalQuery(
    'sen.kata.hira',
    'かーど',
    EvalCategory.sentinel,
    expect: [Expect('カード', maxRank: 5)],
  ),
  EvalQuery(
    'sen.romaji.taberu',
    'taberu',
    EvalCategory.sentinel,
    expect: [Expect('食べる', maxRank: 3)],
  ),
  EvalQuery(
    'sen.romaji.nihongo',
    'nihongo',
    EvalCategory.sentinel,
    expect: [Expect('日本語', maxRank: 3)],
  ),
  EvalQuery(
    'sen.romaji.kaado',
    'kaado',
    EvalCategory.sentinel,
    expect: [Expect('カード', maxRank: 5)],
  ),
  EvalQuery(
    'sen.en.eat',
    'eat',
    EvalCategory.sentinel,
    expect: [Expect('食べる', maxRank: 20)],
  ),
  EvalQuery(
    'sen.en.school',
    'school',
    EvalCategory.sentinel,
    expect: [Expect('学校', maxRank: 20)],
  ),
  EvalQuery(
    'sen.en.teacher',
    'teacher',
    EvalCategory.sentinel,
    expect: [Expect('先生', maxRank: 20)],
  ),

  // --- New-feature checks: what 350f367 claims to deliver. ---
  EvalQuery(
    'new.renai',
    'renai',
    EvalCategory.newFeature,
    expect: [Expect('恋愛', maxRank: 5)],
  ),
  EvalQuery(
    'new.rennai',
    'rennai',
    EvalCategory.newFeature,
    expect: [Expect('恋愛', maxRank: 5)],
  ),
  EvalQuery(
    'new.renai.apos',
    "ren'ai",
    EvalCategory.newFeature,
    expect: [Expect('恋愛', maxRank: 3)],
  ),
  EvalQuery(
    'new.kinen',
    'kinen',
    EvalCategory.newFeature,
    expect: [Expect('記念', maxRank: 10), Expect('禁煙', maxRank: 10)],
    note: 'both readings are real words and must coexist',
  ),
  EvalQuery(
    'new.konnyaku',
    'konnyaku',
    EvalCategory.newFeature,
    expect: [Expect('蒟蒻', maxRank: 10), Expect('婚約')],
    note: '婚約 is the こんやく fork — rank recorded, not judged',
  ),
  EvalQuery(
    'new.gakko',
    'gakko',
    EvalCategory.newFeature,
    expect: [Expect('学校', maxRank: 5)],
  ),
  EvalQuery(
    'new.kyo',
    'kyo',
    EvalCategory.newFeature,
    expect: [Expect('今日', maxRank: 10)],
  ),
  EvalQuery(
    'new.arigato',
    'arigato',
    EvalCategory.newFeature,
    expect: [Expect('ありがとう', maxRank: 10)],
  ),
  EvalQuery(
    'new.benkyo',
    'benkyo',
    EvalCategory.newFeature,
    expect: [Expect('勉強', maxRank: 5)],
  ),
  EvalQuery(
    'new.kyou',
    'kyou',
    EvalCategory.newFeature,
    expect: [Expect('今日', maxRank: 5)],
    note: 'control: already worked',
  ),
  EvalQuery(
    'new.sensei',
    'sensei',
    EvalCategory.newFeature,
    expect: [Expect('先生', maxRank: 3)],
    note: 'control: already worked',
  ),
  EvalQuery(
    'new.onna',
    'onna',
    EvalCategory.newFeature,
    expect: [Expect('女', maxRank: 3)],
    note: 'junk alternate おんあ must not displace the real word',
  ),
  EvalQuery(
    'new.sannen',
    'sannen',
    EvalCategory.newFeature,
    expect: [Expect('三年', maxRank: 10)],
    note: 'junk alternate さんえん must not displace the real word',
  ),

  // --- Noise-risk probes: per-keystroke states; flooding hypothesis. ---
  EvalQuery(
    'noise.kana.ho',
    'ほ',
    EvalCategory.noise,
    note: 'completion-eligible; ほう words (方/法/報) are very frequent',
  ),
  EvalQuery(
    'noise.kana.to',
    'と',
    EvalCategory.noise,
    note: 'completion-eligible',
  ),
  EvalQuery(
    'noise.kana.ko',
    'こ',
    EvalCategory.noise,
    note: 'completion-eligible',
  ),
  EvalQuery(
    'noise.kana.no',
    'の',
    EvalCategory.noise,
    note: 'completion-eligible',
  ),
  EvalQuery(
    'noise.kana.ta',
    'た',
    EvalCategory.noise,
    note: 'control: a-row, no completion',
  ),
  EvalQuery(
    'noise.kana.shi',
    'し',
    EvalCategory.noise,
    note: 'control: i-row, no completion',
  ),
  EvalQuery('noise.romaji.ho', 'ho', EvalCategory.noise),
  EvalQuery('noise.romaji.ko', 'ko', EvalCategory.noise),
  EvalQuery('noise.romaji.ka', 'ka', EvalCategory.noise),
  EvalQuery('noise.romaji.na', 'na', EvalCategory.noise),
  EvalQuery('prog.r', 'r', EvalCategory.noise, note: 'typing renai: 1'),
  EvalQuery('prog.re', 're', EvalCategory.noise, note: 'typing renai: 2'),
  EvalQuery('prog.ren', 'ren', EvalCategory.noise, note: 'typing renai: 3'),
  EvalQuery(
    'prog.rena',
    'rena',
    EvalCategory.noise,
    expect: [Expect('恋愛')],
    note: 'typing renai: 4 — rank recorded',
  ),
  EvalQuery(
    'prog.renai',
    'renai',
    EvalCategory.noise,
    expect: [Expect('恋愛')],
    note: 'typing renai: 5 — rank recorded',
  ),
  EvalQuery('prog.ga', 'が', EvalCategory.noise, note: 'typing がっこう: 1'),
  EvalQuery('prog.gaxtsu', 'がっ', EvalCategory.noise, note: 'typing がっこう: 2'),
  EvalQuery(
    'prog.gakko',
    'がっこ',
    EvalCategory.noise,
    expect: [Expect('学校')],
    note: 'typing がっこう: 3 — completion on',
  ),
  EvalQuery(
    'prog.gakkou',
    'がっこう',
    EvalCategory.noise,
    expect: [Expect('学校', maxRank: 3)],
    note: 'typing がっこう: 4',
  ),

  // --- Pathological inputs. ---
  EvalQuery(
    'path.nana',
    'nanananana',
    EvalCategory.pathological,
    note: 'saturates the ambiguity fork budget',
  ),
  EvalQuery(
    'path.konnichiwa',
    'konnichiwa',
    EvalCategory.pathological,
    expect: [Expect('こんにちは')],
    note: 'rank recorded, not judged',
  ),
  EvalQuery('path.junk', 'kannnennnn', EvalCategory.pathological),
  EvalQuery(
    'path.ohayo',
    'ohayougozaimasu',
    EvalCategory.pathological,
    expect: [Expect('おはようございます')],
    note: 'rank recorded',
  ),
  EvalQuery(
    'path.ohayo.space',
    'ohayou gozaimasu',
    EvalCategory.pathological,
    expect: [Expect('おはようございます')],
    note: 'rank recorded',
  ),
  EvalQuery('path.n', 'n', EvalCategory.pathological),
];

// ---------------------------------------------------------------------------
// Download / cache
// ---------------------------------------------------------------------------

const _redirectStatuses = {301, 302, 303, 307, 308};

Future<void> _download(String url, File dest) async {
  _log('[eval] downloading $url');
  final client = HttpClient();
  try {
    var currentUrl = url;
    for (var redirects = 0; redirects <= 5; redirects++) {
      final request = await client.getUrl(Uri.parse(currentUrl));
      request.followRedirects = false;
      request.headers.set('User-Agent', 'mekuru-eval-harness');
      final response = await request.close();
      if (_redirectStatuses.contains(response.statusCode)) {
        final location = response.headers.value('location');
        await response.drain<void>();
        if (location == null) {
          throw HttpException('redirect without location from $currentUrl');
        }
        currentUrl = Uri.parse(currentUrl).resolve(location).toString();
        continue;
      }
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw HttpException('HTTP ${response.statusCode} for $currentUrl');
      }
      final tmp = File('${dest.path}.tmp');
      final sink = tmp.openWrite();
      final total = response.contentLength;
      var received = 0;
      var lastDecile = -1;
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          final decile = (received * 10) ~/ total;
          if (decile > lastDecile) {
            lastDecile = decile;
            _log('[eval]   ${decile * 10}% of ${total ~/ 1024} KB');
          }
        }
      }
      await sink.close();
      await tmp.rename(dest.path);
      _log('[eval] saved ${dest.path} (${received ~/ 1024} KB)');
      return;
    }
    throw const HttpException('too many redirects');
  } finally {
    client.close();
  }
}

Future<String> _fetchJson(String url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    request.headers.set('Accept', 'application/vnd.github.v3+json');
    request.headers.set('User-Agent', 'mekuru-eval-harness');
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode} for $url: $body');
    }
    return body;
  } finally {
    client.close();
  }
}

Never _missing(_Config cfg, String what, String hint) {
  fail(
    'Eval asset missing: $what. $hint '
    '(cache root: ${cfg.home.path}; set MEKURU_EVAL_OFFLINE=0 or unset it '
    'to allow downloads, or place the file there manually)',
  );
}

Future<String> _resolveJmdictTag(_Config cfg) async {
  if (cfg.pinnedTag != null) return cfg.pinnedTag!;
  if (cfg.jmdictTagFile.existsSync()) {
    final cached = cfg.jmdictTagFile.readAsStringSync().trim();
    if (cached.isNotEmpty) return cached;
  }
  if (cfg.offline) {
    _missing(cfg, 'JMdict release tag', 'Set MEKURU_EVAL_JMDICT_TAG.');
  }
  final body = await _fetchJson(
    'https://api.github.com/repos/yomidevs/jmdict-yomitan/releases/latest',
  );
  final tag = (jsonDecode(body) as Map<String, dynamic>)['tag_name'] as String;
  cfg.jmdictTagFile.writeAsStringSync(tag);
  _log('[eval] JMdict release tag: $tag');
  return tag;
}

Future<void> _ensureZips(_Config cfg) async {
  cfg.cacheDir.createSync(recursive: true);
  if (!cfg.jmdictZip.existsSync()) {
    if (cfg.offline) {
      _missing(cfg, cfg.jmdictZip.path, 'Download JMdict_english.zip.');
    }
    final tag = await _resolveJmdictTag(cfg);
    await _download(
      'https://github.com/yomidevs/jmdict-yomitan/releases/download/'
      '$tag/JMdict_english.zip',
      cfg.jmdictZip,
    );
  }
  if (!cfg.jpdbZip.existsSync()) {
    if (cfg.offline) {
      _missing(cfg, cfg.jpdbZip.path, 'Download the JPDB frequency zip.');
    }
    await _download(_jpdbUrl, cfg.jpdbZip);
  }
}

// ---------------------------------------------------------------------------
// Master DB
// ---------------------------------------------------------------------------

Future<bool> _dbLooksReady(File dbFile) async {
  if (!dbFile.existsSync()) return false;
  final db = AppDatabase(NativeDatabase(dbFile));
  try {
    final repo = DictionaryRepository(db);
    final dicts = await repo.getAllDictionaries();
    final hasJmdict = dicts.any((d) => d.name.startsWith('JMdict'));
    final hasJpdb = dicts.any((d) => d.name == _jpdbDictName);
    final count = await repo.getTotalEntryCount();
    return hasJmdict && hasJpdb && count > 100000;
  } catch (_) {
    return false;
  } finally {
    await db.close();
  }
}

Future<void> _ensureMasterDb(_Config cfg) async {
  cfg.dbDir.createSync(recursive: true);
  if (cfg.rebuildDb && cfg.masterDb.existsSync()) {
    cfg.masterDb.deleteSync();
  }
  if (await _dbLooksReady(cfg.masterDb)) {
    _log('[eval] reusing master DB ${cfg.masterDb.path}');
    return;
  }
  await _ensureZips(cfg);

  if (cfg.buildingDb.existsSync()) cfg.buildingDb.deleteSync();
  _log('[eval] building master DB (one-time; several minutes)...');
  final sw = Stopwatch()..start();
  final db = AppDatabase(NativeDatabase(cfg.buildingDb));
  try {
    final repo = DictionaryRepository(db);
    final importer = DictionaryImporter(repo);

    var lastDecile = -1;
    _log('[eval] importing JMdict...');
    final jmdictCount = await importer.importFromFile(
      cfg.jmdictZip.path,
      onProgress: (processed, total) {
        if (total <= 0) return;
        final decile = (processed * 10) ~/ total;
        if (decile > lastDecile) {
          lastDecile = decile;
          _log(
            '[eval]   JMdict ${decile * 10}% '
            '(${sw.elapsed.inSeconds}s elapsed)',
          );
        }
      },
    );
    _log('[eval] JMdict imported: $jmdictCount entries');

    _log('[eval] importing JPDB frequency dictionary...');
    final jpdbCount = await importer.importFromFile(cfg.jpdbZip.path);
    _log('[eval] JPDB imported: $jpdbCount rows');

    // Mirror JpdbFreqDownloadService: frequency-only install pattern.
    final jpdbMeta = await repo.getDictionaryByName(_jpdbDictName);
    if (jpdbMeta == null) {
      fail('JPDB dictionary "$_jpdbDictName" not found after import');
    }
    await repo.toggleDictionary(jpdbMeta.id, isEnabled: false);
    await repo.setHidden(jpdbMeta.id, isHidden: true);

    final dicts = await repo.getAllDictionaries();
    final jmdictMeta = dicts.firstWhere((d) => d.name.startsWith('JMdict'));
    final total = await repo.getTotalEntryCount();
    _log(
      '[eval] master DB ready in ${sw.elapsed.inMinutes}m'
      '${sw.elapsed.inSeconds % 60}s: JMdict title="${jmdictMeta.name}" '
      '(enabled=${jmdictMeta.isEnabled}), $total total entries',
    );
    if (total <= 100000) {
      fail('suspiciously small import: $total entries');
    }
  } finally {
    await db.close();
  }
  cfg.buildingDb.renameSync(cfg.masterDb.path);
}

// ---------------------------------------------------------------------------
// Measurement
// ---------------------------------------------------------------------------

class _Card {
  _Card(
    this.expression,
    this.reading,
    this.frequencyRank,
    this.dictionary,
    this.gloss,
  );

  final String expression;
  final String reading;
  final int? frequencyRank;
  final String dictionary;
  final String gloss;
}

List<_Card> _toCards(List<DictionaryEntryWithSource> results) {
  final seen = <(String, String)>{};
  final cards = <_Card>[];
  for (final r in results) {
    final key = (r.entry.expression, r.entry.reading);
    if (!seen.add(key)) continue;
    final glosses = GlossaryParser.parse(r.entry.glossaries);
    var gloss = glosses.isEmpty ? '' : glosses.first;
    if (gloss.length > 60) gloss = gloss.substring(0, 60);
    cards.add(
      _Card(
        r.entry.expression,
        r.entry.reading,
        r.frequencyRank,
        r.dictionaryName,
        gloss,
      ),
    );
  }
  return cards;
}

/// Forms of the query "as typed" (orthographic equivalents that exist at
/// every commit). Used for the commit-agnostic flooding signal.
Set<String> _typedForms(String query) {
  final forms = <String>{
    query,
    RomajiConverter.katakanaToHiragana(query),
    RomajiConverter.hiraganaToKatakana(query),
  };
  if (RomajiConverter.isRomaji(query)) {
    final kana = RomajiConverter.convert(query);
    if (kana.isNotEmpty) {
      forms.add(kana);
      forms.add(RomajiConverter.hiraganaToKatakana(kana));
    }
  }
  forms.remove('');
  return forms;
}

Future<Map<String, dynamic>> _measureQuery(
  DictionaryQueryService svc,
  EvalQuery q,
  _Config cfg,
) async {
  final times = <int>[];
  List<DictionaryEntryWithSource> results = const [];
  for (var i = 0; i < cfg.reps; i++) {
    final sw = Stopwatch()..start();
    results = await svc.fuzzySearchWithSource(q.query);
    sw.stop();
    times.add(sw.elapsedMicroseconds);
  }
  times.sort();

  final cards = _toCards(results);
  final typed = _typedForms(q.query);
  final top10 = cards.take(10).toList();
  final exactTypedInTop10 = top10
      .where((c) => typed.contains(c.expression) || typed.contains(c.reading))
      .length;

  int rankOf(String target) {
    for (var i = 0; i < cards.length; i++) {
      if (cards[i].expression == target || cards[i].reading == target) {
        return i;
      }
    }
    return -1;
  }

  final expectations = <Map<String, dynamic>>[];
  for (final e in q.expect) {
    final rank = rankOf(e.target);
    expectations.add({
      'target': e.target,
      'maxRank': e.maxRank,
      'rank': rank,
      'pass': e.maxRank == null ? null : rank != -1 && rank <= e.maxRank!,
    });
  }

  return {
    'id': q.id,
    'query': q.query,
    'category': q.category.name,
    'note': q.note,
    'medianMicros': times[times.length ~/ 2],
    'minMicros': times.first,
    'maxMicros': times.last,
    'micros': times,
    'resultCount': results.length,
    'cardCount': cards.length,
    'exactTypedInTop10': exactTypedInTop10,
    'top': [
      for (final c in cards.take(cfg.topN))
        {
          'expression': c.expression,
          'reading': c.reading,
          'freq': c.frequencyRank,
          'dict': c.dictionary,
          'gloss': c.gloss,
        },
    ],
    'expectations': expectations,
  };
}

String _gitCommit() {
  try {
    final result = Process.runSync('git', ['rev-parse', '--short', 'HEAD']);
    if (result.exitCode == 0) return (result.stdout as String).trim();
  } catch (_) {}
  return 'unknown';
}

// ---------------------------------------------------------------------------
// Test
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
  });

  test('real-JMdict search evaluation', () async {
    final cfg = _Config(Platform.environment);
    cfg.runsDir.createSync(recursive: true);

    await _ensureMasterDb(cfg);

    // Work on a private copy so the master stays pristine and two A/B
    // runs can never collide on a database lock.
    final work = File('${cfg.runsDir.path}/${cfg.label}.work.sqlite');
    cfg.masterDb.copySync(work.path);
    for (final suffix in ['-wal', '-shm']) {
      final side = File('${cfg.masterDb.path}$suffix');
      if (side.existsSync()) side.copySync('${work.path}$suffix');
    }
    addTearDown(() {
      for (final f in [
        work,
        File('${work.path}-wal'),
        File('${work.path}-shm'),
      ]) {
        if (f.existsSync()) f.deleteSync();
      }
    });

    final db = AppDatabase(NativeDatabase(work));
    addTearDown(db.close);
    final repo = DictionaryRepository(db);
    final svc = DictionaryQueryService(db);
    svc.invalidateMetasCache();

    final dicts = await repo.getAllDictionaries();
    final entryCount = await repo.getTotalEntryCount();
    final jmdictMeta = dicts.firstWhere((d) => d.name.startsWith('JMdict'));
    final tag = await _resolveJmdictTag(cfg);
    _log(
      '[eval] db: ${dicts.length} dictionaries, $entryCount entries, '
      'JMdict="${jmdictMeta.name}" tag=$tag',
    );

    // Sanity gates — must hold at every commit (never assert new-feature
    // behavior here; the differ judges that).
    final taberu = _toCards(await svc.fuzzySearchWithSource('食べる'));
    expect(taberu.first.expression, '食べる');
    final gakkou = _toCards(await svc.fuzzySearchWithSource('学校'));
    expect(gakkou.first.expression, '学校');
    expect(await svc.fuzzySearchWithSource('eat'), isNotEmpty);

    // Warmup.
    for (var i = 0; i < cfg.warmups; i++) {
      for (final q in _battery) {
        await svc.fuzzySearchWithSource(q.query);
      }
    }

    // Measure.
    final wall = Stopwatch()..start();
    final queries = <Map<String, dynamic>>[];
    for (final q in _battery) {
      queries.add(await _measureQuery(svc, q, cfg));
    }
    wall.stop();

    final medians = queries.map((q) => q['medianMicros'] as int).toList()
      ..sort();
    final aggregate = {
      'p50': medians[medians.length ~/ 2],
      'p95': medians[(medians.length * 95) ~/ 100],
      'mean': medians.reduce((a, b) => a + b) / medians.length,
      'totalWallMillis': wall.elapsedMilliseconds,
    };

    final commit = _gitCommit();
    final dictNames = dicts.map((d) => d.name).join('|');
    final output = {
      'schema': 1,
      'label': cfg.label,
      'commit': commit,
      'generatedAt': DateTime.now().toIso8601String(),
      'db': {
        'fingerprint': '$entryCount|$dictNames|$tag',
        'entryCount': entryCount,
        'jmdictTag': tag,
        'jmdictName': jmdictMeta.name,
        'dictionaries': [
          for (final d in dicts)
            {'name': d.name, 'enabled': d.isEnabled, 'hidden': d.isHidden},
        ],
      },
      'config': {'reps': cfg.reps, 'warmups': cfg.warmups, 'topN': cfg.topN},
      'queries': queries,
      'aggregate': aggregate,
    };

    final outFile = File('${cfg.runsDir.path}/${cfg.label}.json');
    outFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(output),
    );
    _log('[eval] wrote ${outFile.path}');

    // Human summary.
    _log('');
    _log(
      '=== eval "${cfg.label}" ($commit) — '
      'p50 ${aggregate['p50']}us p95 ${aggregate['p95']}us ===',
    );
    for (final cat in EvalCategory.values) {
      _log('--- ${cat.name} ---');
      for (final q in queries.where((q) => q['category'] == cat.name)) {
        final exps = (q['expectations'] as List)
            .map(
              (e) =>
                  '${e['target']}@${e['rank']}'
                  '${e['pass'] == false ? ' FAIL' : ''}',
            )
            .join(' ');
        _log(
          '${(q['query'] as String).padRight(18)} '
          '${((q['medianMicros'] as int) / 1000).toStringAsFixed(1)}ms  '
          'res=${q['resultCount']} cards=${q['cardCount']} '
          'typedTop10=${q['exactTypedInTop10']}  $exps',
        );
        if (cat == EvalCategory.noise ||
            (q['expectations'] as List).any((e) => e['pass'] == false)) {
          for (final t in (q['top'] as List).take(5)) {
            _log(
              '    ${t['expression']} [${t['reading']}] '
              'freq=${t['freq']} — ${t['gloss']}',
            );
          }
        }
      }
    }
  }, timeout: const Timeout(Duration(minutes: 45)));
}
