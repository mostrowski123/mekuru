import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/features/backup/data/services/full_backup_service.dart'
    show InsufficientSpaceException;
import 'package:mekuru/features/dictionary/data/models/dictionary_catalog.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_download_service.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';

/// State of one catalog dictionary's download.
class CatalogDownloadState {
  const CatalogDownloadState({
    this.isDownloading = false,
    this.isDeleting = false,
    this.progress = 0,
    this.error,
    this.neededBytes,
    this.wifiLost = false,
  });

  final bool isDownloading;
  final bool isDeleting;

  /// [DictionaryDownloadService] progress: downloading, then importing.
  final double progress;

  /// Why the last attempt failed, shown under the tile.
  final String? error;

  /// The last attempt stopped before downloading: this many more bytes
  /// must be free.
  final int? neededBytes;

  /// The last attempt started on Wi-Fi and stopped when Wi-Fi went.
  final bool wifiLost;
}

/// Downloads one catalog dictionary at a time and reports how it goes.
class CatalogDownloadNotifier extends Notifier<CatalogDownloadState> {
  CatalogDownloadNotifier(this.entry);

  final CatalogDictionary entry;

  @override
  CatalogDownloadState build() => const CatalogDownloadState();

  /// Downloads and imports [entry]. Does nothing while a download runs or
  /// once the dictionary is installed.
  Future<void> download() async {
    if (state.isDownloading || state.isDeleting) return;
    state = const CatalogDownloadState(isDownloading: true);
    try {
      final repository = ref.read(dictionaryRepositoryProvider);
      if (!entry.isInstalledIn(await repository.getAllDictionaries())) {
        await DictionaryDownloadService.downloadAndImportUrl(
          url: entry.url,
          asset: entry.name,
          importer: ref.read(dictionaryImporterProvider),
          requiredBytes: (entry.requiredMb * 1e6).round(),
          onProgress: (progress) => state = CatalogDownloadState(
            isDownloading: true,
            progress: progress,
          ),
        );
      }
      state = const CatalogDownloadState();
    } on DownloadStoppedException {
      // iOS ended the background work, or the user stopped it there.
      state = const CatalogDownloadState();
    } on InsufficientSpaceException catch (e) {
      state = CatalogDownloadState(neededBytes: e.neededBytes);
    } on WifiLostException {
      state = const CatalogDownloadState(wifiLost: true);
    } catch (e) {
      state = CatalogDownloadState(error: '$e');
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
    } finally {
      state = const CatalogDownloadState();
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
