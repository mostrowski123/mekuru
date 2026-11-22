import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/features/settings/data/services/jpdb_freq_download_service.dart';
import 'package:mekuru/features/settings/data/services/yomitan_dict_download_service.dart';
import 'package:mekuru/shared/downloads/download_tile_state.dart';

/// A dictionary with a download tile of its own.
enum FixedDictionary {
  jmdict(YomitanDictType.jmdictEnglish, logTag: 'JMdict'),
  kanjidic(YomitanDictType.kanjidicEnglish, logTag: 'KANJIDIC'),
  jpdb(null, logTag: 'JpdbFreq');

  const FixedDictionary(this.yomitanType, {required this.logTag});

  /// The edition [YomitanDictDownloadService] downloads unless told
  /// otherwise, and always finds (by name prefix) and deletes: JMdict counts
  /// as English whichever variant was downloaded. Null for JPDB, which
  /// [JpdbFreqDownloadService] finds by its one exact name.
  final YomitanDictType? yomitanType;

  final String logTag;
}

/// Downloads, finds and deletes one [FixedDictionary].
class FixedDictionaryNotifier extends DownloadTileNotifier {
  FixedDictionaryNotifier(this.dictionary);

  final FixedDictionary dictionary;

  /// Check whether the dictionary is already imported.
  @override
  Future<void> checkStatus() => checking(dictionary.logTag, () async {
    final repository = ref.read(dictionaryRepositoryProvider);
    final type = dictionary.yomitanType;
    return (
      installed: type == null
          ? await JpdbFreqDownloadService.isImported(repository)
          : await YomitanDictDownloadService.isImported(type, repository),
      fileCount: 0,
    );
  });

  /// Download and import the dictionary over [network]. [variant] picks
  /// JMdict's edition, English when not given; the other two have one.
  @override
  Future<void> download(NetworkConsent network, [YomitanDictType? variant]) {
    assert(variant == null || dictionary == FixedDictionary.jmdict);
    return downloading((onProgress) async {
      final repository = ref.read(dictionaryRepositoryProvider);
      final importer = ref.read(dictionaryImporterProvider);
      final type = dictionary.yomitanType;
      if (type == null) {
        await JpdbFreqDownloadService.downloadAndImport(
          repository: repository,
          importer: importer,
          network: network,
          onProgress: onProgress,
        );
      } else {
        await YomitanDictDownloadService.downloadAndImport(
          type: variant ?? type,
          repository: repository,
          importer: importer,
          network: network,
          onProgress: onProgress,
        );
      }
      return 0;
    });
  }

  /// Delete the dictionary.
  @override
  Future<void> delete() => deleting(() async {
    final repository = ref.read(dictionaryRepositoryProvider);
    final type = dictionary.yomitanType;
    if (type == null) {
      await JpdbFreqDownloadService.delete(repository);
    } else {
      await YomitanDictDownloadService.delete(type, repository);
    }
  });
}

/// Not auto-disposed: a download keeps going after its screen closes.
final fixedDictionaryProvider =
    NotifierProvider.family<
      FixedDictionaryNotifier,
      DownloadTileState,
      FixedDictionary
    >(FixedDictionaryNotifier.new);
