import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/utils/atomic_file.dart';
import 'package:mekuru/features/library/presentation/providers/library_providers.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/data/services/manga_lookup_override_storage.dart';
import 'package:mekuru/features/manga/data/services/manga_word_lookup_resolver.dart';
import 'package:mekuru/features/manga/data/services/mokuro_word_segmenter.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:path/path.dart' as p;

/// Loads and caches the mokuro page data for a manga book.
///
/// The [bookId] is used to look up the book's `filePath` (cache directory),
/// then reads `pages_cache.json` to get all page/block/word data.
///
/// autoDispose: the reader's build keeps it alive while open; closing the
/// reader releases the parsed book graph instead of retaining every opened
/// manga for the app's lifetime. Reopening re-reads pages_cache.json.
final mangaPagesProvider = FutureProvider.autoDispose.family<MokuroBook, int>((
  ref,
  bookId,
) async {
  final bookRepo = ref.read(bookRepositoryProvider);
  final book = await bookRepo.getBookById(bookId);
  if (book == null) throw Exception('Book not found');

  final cacheFile = File(p.join(book.filePath, 'pages_cache.json'));
  if (!await cacheFile.exists()) {
    throw Exception('Pages cache not found. Try re-importing this manga.');
  }
  final content = await cacheFile.readAsString();
  final json = jsonDecode(content) as Map<String, dynamic>;
  final mokuroBook = MokuroBook.fromJson(json);

  // Self-heal caches with missing word boxes (legacy/partial OCR), broken
  // ones (segmented while MeCab was still initializing), or ones segmented
  // with a different dictionary than tap-time lookups tokenize with (the
  // OCR worker stays on IPADIC while this session may have upgraded to
  // UniDic-lite), so overlays stay available and consistent after restarts.
  // The decision — including when to wait for MeCab init or for a pending
  // dictionary upgrade — lives in MokuroWordSegmenter.needsResegmentation.
  if (await MokuroWordSegmenter.needsResegmentation(mokuroBook.pages)) {
    // The cache JSON comes back already encoded by the worker isolate — for
    // a long volume that's a multi-MB string build kept off the UI isolate.
    final (
      book: updated,
      cacheJson: updatedJson,
    ) = await MokuroWordSegmenter.segmentBookInBackground(
      mokuroBook,
      onlyStale: true,
    );
    // Only rewrite the cache when re-segmentation actually changed it (null
    // means MeCab was unavailable and nothing did), so a block that trips
    // the repair heuristic but re-segments identically can never cause a
    // rewrite-on-every-open loop.
    if (updatedJson != null && updatedJson != content) {
      await writeStringAtomic(cacheFile, updatedJson);
    }
    return updated;
  }

  return mokuroBook;
});

/// Whether the debug word-overlay boxes are drawn in the manga reader.
/// Session-only by design — resets on every app launch.
class MangaDebugWordOverlayNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setEnabled(bool value) => state = value;
}

final mangaDebugWordOverlayProvider =
    NotifierProvider<MangaDebugWordOverlayNotifier, bool>(
      MangaDebugWordOverlayNotifier.new,
    );

final mangaLookupOverrideStorageProvider = Provider<MangaLookupOverrideStorage>(
  (ref) {
    return MangaLookupOverrideStorage();
  },
);

final mangaWordLookupResolverProvider = Provider<MangaWordLookupResolver>((
  ref,
) {
  final mecab = ref.watch(mecabServiceProvider);
  final compoundResolver = ref.watch(compoundWordResolverProvider);
  return MangaWordLookupResolver(
    identifyWordWithContext: mecab.identifyWordWithContext,
    resolveCompoundWord: compoundResolver.resolve,
  );
});
