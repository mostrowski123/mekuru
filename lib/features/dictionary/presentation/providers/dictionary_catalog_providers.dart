import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/backup/data/services/full_backup_service.dart'
    show InsufficientSpaceException;
import 'package:mekuru/features/dictionary/data/models/dictionary_catalog.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_download_service.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_update_service.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';

/// State of one dictionary download or update.
class CatalogDownloadState {
  const CatalogDownloadState({
    this.isDownloading = false,
    this.progress = 0,
    this.error,
    this.neededBytes,
  });

  final bool isDownloading;

  /// [DictionaryDownloadService] progress: downloading, then importing.
  final double progress;

  /// Why the last attempt failed, shown under the tile.
  final String? error;

  /// The last attempt stopped before downloading: this many more bytes
  /// must be free.
  final int? neededBytes;
}

/// Runs one dictionary download at a time and reports it.
abstract class _DownloadNotifier extends Notifier<CatalogDownloadState> {
  @override
  CatalogDownloadState build() => const CatalogDownloadState();

  Future<void> run(
    Future<void> Function(void Function(double progress) onProgress) work,
  ) async {
    if (state.isDownloading) return;
    state = const CatalogDownloadState(isDownloading: true);
    try {
      await work(
        (progress) => state = CatalogDownloadState(
          isDownloading: true,
          progress: progress,
        ),
      );
      state = const CatalogDownloadState();
    } on InsufficientSpaceException catch (e) {
      state = CatalogDownloadState(neededBytes: e.neededBytes);
    } catch (e) {
      state = CatalogDownloadState(error: '$e');
    }
  }
}

class CatalogDownloadNotifier extends _DownloadNotifier {
  CatalogDownloadNotifier(this.entry);

  final CatalogDictionary entry;

  /// Downloads and imports [entry]. Does nothing while a download runs or
  /// once the dictionary is installed.
  Future<void> download() => run((onProgress) async {
    final repository = ref.read(dictionaryRepositoryProvider);
    if (entry.isInstalledIn(await repository.getAllDictionaries())) return;
    await DictionaryDownloadService.downloadAndImportUrl(
      url: entry.url,
      asset: entry.name,
      importer: ref.read(dictionaryImporterProvider),
      requiredBytes: (entry.requiredMb * 1e6).round(),
      onProgress: onProgress,
    );
  });
}

/// Not auto-disposed: a download keeps going after its screen closes.
final catalogDownloadProvider =
    NotifierProvider.family<
      CatalogDownloadNotifier,
      CatalogDownloadState,
      CatalogDictionary
    >(CatalogDownloadNotifier.new);

final dictionaryUpdateServiceProvider = Provider<DictionaryUpdateService>(
  (ref) => DictionaryUpdateService(ref.watch(dictionaryRepositoryProvider)),
);

/// Updates for the installed dictionaries, by dictionary id. Checked once
/// per app session, when a screen that offers updates first shows: a few
/// small index files, not a check on every change to the list.
final dictionaryUpdatesProvider = FutureProvider<Map<int, DictionaryUpdate>>((
  ref,
) async {
  final service = ref.watch(dictionaryUpdateServiceProvider);
  final dictionaries = await ref.read(dictionariesProvider.future);
  final checks = await Future.wait([
    for (final d in dictionaries)
      service.checkForUpdate(d).then((u) => (d.id, u)),
  ]);
  return {for (final (id, update) in checks) id: ?update};
});

class DictionaryUpdateNotifier extends _DownloadNotifier {
  DictionaryUpdateNotifier(this.dictionaryId);

  final int dictionaryId;

  /// Replaces the dictionary with the update [dictionaryUpdatesProvider]
  /// found for it.
  Future<void> update() => run((onProgress) async {
    final update = ref.read(dictionaryUpdatesProvider).value?[dictionaryId];
    final dictionaries = await ref
        .read(dictionaryRepositoryProvider)
        .getAllDictionaries();
    final old = dictionaries.where((d) => d.id == dictionaryId).firstOrNull;
    if (update == null || old == null) return;
    await ref
        .read(dictionaryUpdateServiceProvider)
        .apply(
          old,
          update,
          importer: ref.read(dictionaryImporterProvider),
          onProgress: onProgress,
        );
  });
}

/// Not auto-disposed: an update keeps going after its screen closes.
final dictionaryUpdateProvider =
    NotifierProvider.family<
      DictionaryUpdateNotifier,
      CatalogDownloadState,
      int
    >(DictionaryUpdateNotifier.new);
