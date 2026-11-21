import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/features/settings/data/services/jpdb_freq_download_service.dart';
import 'package:mekuru/features/settings/data/services/yomitan_dict_download_service.dart';
import 'package:mekuru/main.dart' show appL10n;
import 'package:mekuru/shared/widgets/download_status.dart';

/// A dictionary with a download tile of its own, and the English messages
/// that tile shows.
enum FixedDictionary {
  jmdict(
    YomitanDictType.jmdictEnglish,
    logTag: 'JMdict',
    downloaded: 'JMdict downloaded successfully.',
    deleted: 'JMdict deleted.',
  ),
  kanjidic(
    YomitanDictType.kanjidicEnglish,
    logTag: 'KANJIDIC',
    downloaded: 'KANJIDIC downloaded successfully.',
    deleted: 'KANJIDIC deleted.',
  ),
  jpdb(
    null,
    logTag: 'JpdbFreq',
    downloaded: 'Frequency dictionary downloaded successfully.',
    deleted: 'Frequency dictionary deleted.',
  );

  const FixedDictionary(
    this.yomitanType, {
    required this.logTag,
    required this.downloaded,
    required this.deleted,
  });

  /// The edition [YomitanDictDownloadService] downloads unless told
  /// otherwise, and always finds (by name prefix) and deletes: JMdict counts
  /// as English whichever variant was downloaded. Null for JPDB, which
  /// [JpdbFreqDownloadService] finds by its one exact name.
  final YomitanDictType? yomitanType;

  final String logTag;
  final String downloaded;
  final String deleted;
}

/// What a [FixedDictionary]'s tile shows.
class FixedDictionaryState {
  final bool isImported;
  final bool isDownloading;
  final bool isDeleting;
  final double progress;
  final String? error;
  final String? successMessage;

  const FixedDictionaryState({
    this.isImported = false,
    this.isDownloading = false,
    this.isDeleting = false,
    this.progress = 0.0,
    this.error,
    this.successMessage,
  });

  FixedDictionaryState copyWith({
    bool? isImported,
    bool? isDownloading,
    bool? isDeleting,
    double? progress,
    String? error,
    String? successMessage,
  }) {
    return FixedDictionaryState(
      isImported: isImported ?? this.isImported,
      isDownloading: isDownloading ?? this.isDownloading,
      isDeleting: isDeleting ?? this.isDeleting,
      progress: progress ?? this.progress,
      error: error,
      successMessage: successMessage,
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
    state = state.copyWith(
      isDownloading: true,
      progress: 0.0,
      error: null,
      successMessage: null,
    );

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
      state = FixedDictionaryState(
        isImported: true,
        successMessage: dictionary.downloaded,
      );
    } catch (e) {
      state = FixedDictionaryState(
        isImported: state.isImported,
        error: dictionaryDownloadError(appL10n(), e),
      );
    }
  }

  /// Delete the dictionary.
  Future<void> delete() async {
    if (state.isDeleting) return;
    state = state.copyWith(isDeleting: true, error: null, successMessage: null);

    try {
      final repository = ref.read(dictionaryRepositoryProvider);
      final type = dictionary.yomitanType;
      if (type == null) {
        await JpdbFreqDownloadService.delete(repository);
      } else {
        await YomitanDictDownloadService.delete(type, repository);
      }
      state = FixedDictionaryState(successMessage: dictionary.deleted);
    } catch (e) {
      state = state.copyWith(isDeleting: false, error: 'Delete failed: $e');
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
