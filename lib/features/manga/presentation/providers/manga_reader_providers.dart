import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/library/presentation/providers/library_providers.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/data/services/mokuro_word_segmenter.dart';
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

  // Self-heal legacy/partial OCR caches that have text blocks but missing
  // word boxes, so overlays remain available after restarts.
  if (_needsWordSegmentation(mokuroBook.pages)) {
    final segmentedPages = await _segmentPagesForLookup(mokuroBook.pages);
    final updated = MokuroBook(
      title: mokuroBook.title,
      imageDirPath: mokuroBook.imageDirPath,
      safTreeUri: mokuroBook.safTreeUri,
      safImageDirRelativePath: mokuroBook.safImageDirRelativePath,
      pages: segmentedPages,
    );
    await cacheFile.writeAsString(jsonEncode(updated.toJson()));
    return updated;
  }

  return mokuroBook;
});

bool _needsWordSegmentation(List<MokuroPage> pages) {
  for (final page in pages) {
    for (final block in page.blocks) {
      if (block.lines.isNotEmpty && block.words.isEmpty) {
        return true;
      }
    }
  }
  return false;
}

Future<List<MokuroPage>> _segmentPagesForLookup(List<MokuroPage> pages) async {
  final strippedPages = pages
      .map(
        (page) => page.copyWith(
          blocks: page.blocks
              .map((block) => block.copyWith(words: const []))
              .toList(),
        ),
      )
      .toList();
  return MokuroWordSegmenter.segmentAllPages(strippedPages);
}

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
