import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/dictionary/data/models/dictionary_catalog.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_download_service.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/features/settings/presentation/providers/fixed_dictionary_providers.dart';
import 'package:mekuru/shared/downloads/download.dart';

/// State of one catalog dictionary's download.
class CatalogDownloadState {
  const CatalogDownloadState({
    this.isDownloading = false,
    this.isDeleting = false,
    this.progress = 0,
    this.failure,
    this.deletedId,
    this.deleteFailed = false,
  });

  final bool isDownloading;
  final bool isDeleting;

  /// [DictionaryDownloadService] progress: downloading, then importing.
  final double progress;

  /// What stopped the last attempt, shown under the tile
  /// (`dictionaryDownloadError`).
  final Object? failure;

  /// The dictionary this tile deleted. The list stream can still show it:
  /// Drift refetches the list only after every delete queued behind this one.
  final int? deletedId;

  /// The last delete failed; the dictionary is still there to delete again.
  final bool deleteFailed;
}

/// Downloads one catalog dictionary at a time and reports how it goes.
class CatalogDownloadNotifier extends Notifier<CatalogDownloadState> {
  CatalogDownloadNotifier(this.entry);

  final CatalogDictionary entry;

  @override
  CatalogDownloadState build() => const CatalogDownloadState();

  /// Downloads and imports [entry] over [network]. Does nothing while a
  /// download runs or once the dictionary is installed. [replaceJmdict]
  /// deletes JMdict English once [entry] is installed, never before, so a
  /// failed download leaves the user's dictionary in place.
  Future<void> download(
    NetworkConsent network, {
    bool replaceJmdict = false,
  }) async {
    if (state.isDownloading || state.isDeleting) return;
    state = const CatalogDownloadState(isDownloading: true);
    try {
      final repository = ref.read(dictionaryRepositoryProvider);
      if (!entry.isInstalledIn(await repository.getAllDictionaries())) {
        await DictionaryDownloadService.downloadAndImportUrl(
          kind: DownloadKind.catalogDictionary,
          url: entry.url,
          asset: entry.name,
          importer: ref.read(dictionaryImporterProvider),
          network: network,
          requiredBytes: (entry.requiredMb * 1e6).round(),
          onProgress: (progress) => state = CatalogDownloadState(
            isDownloading: true,
            progress: progress,
          ),
        );
      }
      state = const CatalogDownloadState();
      // JMdict's own tile shows the delete and anything that stops it.
      final jmdict = fixedDictionaryProvider(FixedDictionary.jmdict);
      if (replaceJmdict) await ref.read(jmdict.notifier).delete();
    } on DownloadStoppedException {
      // iOS ended the background work, or the user stopped it there.
      state = const CatalogDownloadState();
    } catch (e) {
      state = CatalogDownloadState(failure: e);
    }
  }

  /// Deletes [entry], installed as [dictionaryId]. A big dictionary takes a
  /// while, so the tile shows it until done, also after its screen closes.
  Future<void> delete(int dictionaryId) async {
    if (state.isDownloading || state.isDeleting) return;
    state = const CatalogDownloadState(isDeleting: true);
    try {
      await ref
          .read(dictionaryRepositoryProvider)
          .deleteDictionary(dictionaryId);
      state = CatalogDownloadState(deletedId: dictionaryId);
    } catch (e) {
      logFailure('dictionary.delete_failed', e, attrs: {'asset': entry.name});
      state = const CatalogDownloadState(deleteFailed: true);
    }
  }
}

/// Not auto-disposed: a download keeps going after its screen closes.
final catalogDownloadProvider =
    NotifierProvider.family<
      CatalogDownloadNotifier,
      CatalogDownloadState,
      CatalogDictionary
    >(CatalogDownloadNotifier.new);
