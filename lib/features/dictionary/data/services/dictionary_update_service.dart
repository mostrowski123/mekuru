import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/services/http_transport.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/dictionary/data/models/dictionary_catalog.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_download_service.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_importer.dart';
import 'package:mekuru/features/settings/data/services/yomitan_dict_download_service.dart';

/// A newer revision of an installed dictionary, as the index.json at
/// [indexUrl] describes it.
class DictionaryUpdate {
  const DictionaryUpdate({
    required this.downloadUrl,
    required this.indexUrl,
    this.revision,
    this.title,
  });

  final String downloadUrl;
  final String indexUrl;
  final String? revision;
  final String? title;
}

/// Whether [remote] is a later revision than [local]. Runs of digits
/// compare as numbers ("2026.10.03.0", "kanjidic2.2026-276"), the rest as
/// text, so a stale index never offers an older revision.
bool isNewerRevision(String remote, String local) {
  final a = _revisionParts.allMatches(remote).map((m) => m[0]!).toList();
  final b = _revisionParts.allMatches(local).map((m) => m[0]!).toList();
  for (var i = 0; i < a.length && i < b.length; i++) {
    final x = int.tryParse(a[i]);
    final y = int.tryParse(b[i]);
    final order = x != null && y != null
        ? x.compareTo(y)
        : a[i].compareTo(b[i]);
    if (order != 0) return order > 0;
  }
  return a.length > b.length;
}

final _revisionParts = RegExp(r'\d+|\D+');

/// Finds and applies updates to installed dictionaries, through the
/// index.json their publisher keeps current (Yomitan's `indexUrl`).
class DictionaryUpdateService {
  DictionaryUpdateService(this._repository, {http.Client? client})
    : _client = client ?? http.Client();

  final DictionaryRepository _repository;
  final http.Client _client;

  /// Where [meta]'s publisher keeps its index.json; null when unknown.
  /// English JMdict and KANJIDIC imported before Mekuru kept index URLs
  /// get theirs worked out once and saved.
  Future<String?> indexUrlFor(DictionaryMeta meta) async {
    if (meta.indexUrl case final url?) return url;
    if (CatalogDictionary.forTitle(meta.name) case final entry?) {
      return entry.indexUrl;
    }
    final type = await _legacyType(meta);
    if (type == null) return null;
    final url = YomitanDictDownloadService.indexUrl(type);
    await _repository.setIndexUrl(meta.id, url);
    return url;
  }

  Future<YomitanDictType?> _legacyType(DictionaryMeta meta) async {
    if (YomitanDictDownloadService.matches(
      YomitanDictType.jmdictEnglish,
      meta.name,
    )) {
      // Both English editions share a title; only one has examples.
      final examples = await _repository.sampleGlossariesContain(
        meta.id,
        r'\"content\":\"examples\"',
      );
      return examples
          ? YomitanDictType.jmdictEnglishWithExamples
          : YomitanDictType.jmdictEnglish;
    }
    if (YomitanDictDownloadService.matches(
      YomitanDictType.kanjidicEnglish,
      meta.name,
    )) {
      return YomitanDictType.kanjidicEnglish;
    }
    return null;
  }

  /// The update for [meta]: its publisher lists a later revision (or, when
  /// no revision was stored, a later title). Null when there is none or
  /// the check fails: offline, a bad URL, a broken index or a stalled host
  /// all mean no update this time.
  Future<DictionaryUpdate?> checkForUpdate(DictionaryMeta meta) async {
    try {
      return await _check(meta).timeout(const Duration(seconds: 20));
    } catch (_) {
      return null;
    }
  }

  Future<DictionaryUpdate?> _check(DictionaryMeta meta) async {
    final indexUrl = await indexUrlFor(meta);
    if (indexUrl == null || !indexUrl.startsWith('https://')) return null;
    final response = await sendWithTimeout(
      _client,
      http.Request('GET', Uri.parse(indexUrl)),
      timeout: const Duration(seconds: 15),
    );
    if (response.statusCode != 200) return null;
    final index = decodeJsonBody(response);
    if (index is! Map) return null;
    final revision = index['revision'] is String
        ? index['revision'] as String
        : null;
    final title = index['title'] is String ? index['title'] as String : null;
    final downloadUrl = index['downloadUrl'];
    final local = meta.revision;
    final newer = local == null
        ? title != null && isNewerRevision(title, meta.name)
        : revision != null && isNewerRevision(revision, local);
    if (!newer ||
        downloadUrl is! String ||
        !downloadUrl.startsWith('https://')) {
      return null;
    }
    return DictionaryUpdate(
      downloadUrl: downloadUrl,
      indexUrl: indexUrl,
      revision: revision,
      title: title,
    );
  }

  /// Replaces [old] with [update]: imports the new revision, gives it
  /// [old]'s place and enabled state, then deletes [old]. When the download
  /// or import fails, [old] stays as it was.
  Future<void> apply(
    DictionaryMeta old,
    DictionaryUpdate update, {
    required DictionaryImporter importer,
    void Function(double progress)? onProgress,
  }) async {
    final entry = CatalogDictionary.forTitle(old.name);
    final asset = entry?.name ?? 'dictionary';
    // An earlier attempt may have imported this revision and stopped before
    // the swap (the app was closed): finish that one.
    var newId = (await _repository.getAllDictionaries())
        .where((d) => d.id != old.id && _isRevision(d, old, update))
        .firstOrNull
        ?.id;
    if (newId == null) {
      await DictionaryDownloadService.downloadAndImportUrl(
        url: update.downloadUrl,
        asset: asset,
        importer: importer,
        requiredBytes: entry == null ? null : (entry.requiredMb * 1e6).round(),
        // Not done until the swap below is.
        onProgress: (progress) => onProgress?.call(math.min(progress, 0.95)),
        onDictionaryCreated: (id) => newId = id,
      );
    }
    await _repository.replaceDictionary(
      old.id,
      newId ?? (throw StateError('The update imported no dictionary')),
    );
    onProgress?.call(1.0);
    logUsage('dictionary.updated', attrs: {'asset': asset});
  }

  /// Whether [d] is [update]'s revision of [old].
  static bool _isRevision(
    DictionaryMeta d,
    DictionaryMeta old,
    DictionaryUpdate update,
  ) =>
      dictionaryDisplayName(d.name) == dictionaryDisplayName(old.name) &&
      (update.revision == null
          ? d.name == update.title
          : d.revision == update.revision) &&
      // Hugging Face appends ?download=true to its own index URLs.
      (d.indexUrl == null ||
          d.indexUrl!.split('?').first == update.indexUrl.split('?').first);
}
