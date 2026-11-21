import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/features/settings/data/services/jpdb_freq_download_service.dart';
import 'package:mekuru/features/settings/data/services/yomitan_dict_download_service.dart';
import 'package:mekuru/shared/downloads/download.dart';

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

/// What a [FixedDictionary]'s tile shows.
class FixedDictionaryState {
  final bool isImported;
  final bool isDownloading;
  final bool isDeleting;
  final double progress;

  /// The last download or delete, until the next state change.
  final TileOutcome? outcome;

  const FixedDictionaryState({
    this.isImported = false,
    this.isDownloading = false,
    this.isDeleting = false,
    this.progress = 0.0,
    this.outcome,
  });

  FixedDictionaryState copyWith({
    bool? isImported,
    bool? isDownloading,
    bool? isDeleting,
    double? progress,
    TileOutcome? outcome,
  }) {
    return FixedDictionaryState(
      isImported: isImported ?? this.isImported,
      isDownloading: isDownloading ?? this.isDownloading,
      isDeleting: isDeleting ?? this.isDeleting,
      progress: progress ?? this.progress,
      outcome: outcome,
    );
  }
}

/// Downloads, finds and deletes one [FixedDictionary].
class FixedDictionaryNotifier extends Notifier<FixedDictionaryState> {
  FixedDictionaryNotifier(this.dictionary);

  final FixedDictionary dictionary;

  @override
  FixedDictionaryState build() => const FixedDictionaryState();

  /// Check whether the dictionary is already imported.
  Future<void> checkStatus() async {
    try {
      final repository = ref.read(dictionaryRepositoryProvider);
      final type = dictionary.yomitanType;
      final imported = type == null
          ? await JpdbFreqDownloadService.isImported(repository)
          : await YomitanDictDownloadService.isImported(type, repository);
      state = state.copyWith(isImported: imported);
    } catch (e) {
      debugPrint('[${dictionary.logTag}] Error checking status: $e');
    }
  }

  /// Download and import the dictionary over [network]. [variant] picks
  /// JMdict's edition, English when not given; the other two have one.
  Future<void> download(
    NetworkConsent network, [
    YomitanDictType? variant,
  ]) async {
    assert(variant == null || dictionary == FixedDictionary.jmdict);
    if (state.isDownloading) return;
    state = state.copyWith(isDownloading: true, progress: 0.0);

    try {
      final repository = ref.read(dictionaryRepositoryProvider);
      final importer = ref.read(dictionaryImporterProvider);
      void onProgress(double progress) =>
          state = state.copyWith(progress: progress);
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
      state = const FixedDictionaryState(
        isImported: true,
        outcome: (action: TileAction.download, error: null),
      );
    } catch (e) {
      state = FixedDictionaryState(
        isImported: state.isImported,
        outcome: (action: TileAction.download, error: e),
      );
    }
  }

  /// Delete the dictionary.
  Future<void> delete() async {
    if (state.isDeleting) return;
    state = state.copyWith(isDeleting: true);

    try {
      final repository = ref.read(dictionaryRepositoryProvider);
      final type = dictionary.yomitanType;
      if (type == null) {
        await JpdbFreqDownloadService.delete(repository);
      } else {
        await YomitanDictDownloadService.delete(type, repository);
      }
      state = const FixedDictionaryState(
        outcome: (action: TileAction.delete, error: null),
      );
    } catch (e) {
      state = state.copyWith(
        isDeleting: false,
        outcome: (action: TileAction.delete, error: e),
      );
    }
  }
}

/// Not auto-disposed: a download keeps going after its screen closes.
final fixedDictionaryProvider =
    NotifierProvider.family<
      FixedDictionaryNotifier,
      FixedDictionaryState,
      FixedDictionary
    >(FixedDictionaryNotifier.new);
