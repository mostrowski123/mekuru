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

/// Manga view modes.
enum MangaViewMode { singlePage, twoPageSpread, scroll }

/// Reading direction for manga pages.
enum MangaReadingDirection { rtl, ltr }

/// Loads and caches the mokuro page data for a manga book.
///
/// The [bookId] is used to look up the book's `filePath` (cache directory),
/// then reads `pages_cache.json` to get all page/block/word data.
final mangaPagesProvider = FutureProvider.family<MokuroBook, int>((
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
    final segmentedPages =
        await MokuroWordSegmenter.segmentAllPagesInBackground(
          mokuroBook.pages,
          onlyStale: true,
        );
    final updated = MokuroBook(
      title: mokuroBook.title,
      imageDirPath: mokuroBook.imageDirPath,
      safTreeUri: mokuroBook.safTreeUri,
      safImageDirRelativePath: mokuroBook.safImageDirRelativePath,
      autoCropVersion: mokuroBook.autoCropVersion,
      ocrSource: mokuroBook.ocrSource,
      ocrCompleted: mokuroBook.ocrCompleted,
      pages: segmentedPages,
    );
    // Only rewrite the cache when re-segmentation actually changed it, so a
    // block that trips the repair heuristic but re-segments identically can
    // never cause a rewrite-on-every-open loop.
    final updatedJson = jsonEncode(updated.toJson());
    if (updatedJson != content) {
      await writeStringAtomic(cacheFile, updatedJson);
    }
    return updated;
  }

  return mokuroBook;
});

/// Current manga view mode.
class MangaViewModeNotifier extends Notifier<MangaViewMode> {
  @override
  MangaViewMode build() => MangaViewMode.singlePage;

  void setMode(MangaViewMode mode) => state = mode;
}

final mangaViewModeProvider =
    NotifierProvider<MangaViewModeNotifier, MangaViewMode>(
      MangaViewModeNotifier.new,
    );

/// Whether auto-crop is enabled.
class MangaAutoCropNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;

  void setEnabled(bool value) => state = value;
}

final mangaAutoCropProvider = NotifierProvider<MangaAutoCropNotifier, bool>(
  MangaAutoCropNotifier.new,
);

/// Reading direction for manga.
class MangaReadingDirectionNotifier extends Notifier<MangaReadingDirection> {
  @override
  MangaReadingDirection build() => MangaReadingDirection.rtl;

  void toggle() => state = state == MangaReadingDirection.rtl
      ? MangaReadingDirection.ltr
      : MangaReadingDirection.rtl;
}

final mangaReadingDirectionProvider =
    NotifierProvider<MangaReadingDirectionNotifier, MangaReadingDirection>(
      MangaReadingDirectionNotifier.new,
    );

/// Whether the manga lookup sheet uses a transparent background.
class MangaLookupTransparencyNotifier extends Notifier<bool> {
  @override
  bool build() => true; // transparent by default

  void toggle() => state = !state;
}

final mangaLookupTransparencyProvider =
    NotifierProvider<MangaLookupTransparencyNotifier, bool>(
      MangaLookupTransparencyNotifier.new,
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
