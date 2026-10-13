import 'package:mekuru/features/library/data/services/epub_manga_converter.dart';
import 'package:mekuru/features/library/data/services/epub_parser.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/data/services/cbz_parser.dart';
import 'package:path/path.dart' as p;

/// A picture for the zoom viewer: its file and pixel size.
typedef ZoomImage = ({String path, int width, int height});

/// [epubZoomImages] as a compute() entry point: (contentDir, sectionHref,
/// imageIndex, rtl).
Future<List<ZoomImage>?> epubZoomImagesJob((String, String, int, bool) args) =>
    epubZoomImages(args.$1, args.$2, args.$3, rtl: args.$4);

/// The pictures to zoom into for the [imageIndex]th image (`img`, or
/// `image` inside an `svg`, in document order) of the section [sectionHref]
/// (as epub.js names it: relative to the OPF) of the book extracted at
/// [contentDir], left first.
///
/// A page declared as one half of a spread is joined with the other half,
/// when the neighbouring section on that side is a single-image page
/// declared as the opposite half: in right-to-left books a right half opens
/// a spread and looks at the next section, a left half at the previous one.
/// The book's own page-progression-direction decides that, whichever way it
/// is read; [rtl] stands in when the book declares none.
///
/// Null when there is nothing to show (the book folder or the image is
/// missing or broken, the index is out of range, or a path leaves the book
/// folder). Never throws.
Future<List<ZoomImage>?> epubZoomImages(
  String contentDir,
  String sectionHref,
  int imageIndex, {
  required bool rtl,
}) async {
  try {
    final opfPath = await EpubParser.findOpfPath(contentDir);
    if (opfPath == null) return null;
    final docPath = resolveEpubHref(p.posix.dirname(opfPath), sectionHref);
    if (docPath == null) return null;
    final images = await epubDocImages(contentDir, docPath);
    if (imageIndex < 0 || imageIndex >= images.length) return null;
    final image = images[imageIndex];
    if (image == null) return null;

    var paths = [image];
    final book = await readEpubSpine(contentDir);
    final spine = book?.docs ?? const [];
    final at = spine.indexWhere((doc) => doc.path == docPath);
    final side = at < 0 ? null : spine[at].spread;
    if (side == MangaPageSpread.left || side == MangaPageSpread.right) {
      final isLeft = side == MangaPageSpread.left;
      final other = at + (isLeft == (book?.rtl ?? rtl) ? -1 : 1);
      if (other >= 0 &&
          other < spine.length &&
          spine[other].spread ==
              (isLeft ? MangaPageSpread.right : MangaPageSpread.left)) {
        final partner = await singleImageOf(contentDir, spine[other].path);
        if (partner != null) {
          paths = isLeft ? [image, partner] : [partner, image];
        }
      }
    }

    final result = <ZoomImage>[];
    for (final path in paths) {
      final file = p.join(contentDir, path);
      if (!p.isWithin(contentDir, file)) return null;
      final size = await readImageDimensionsFromFile(file);
      if (size == null) return null;
      result.add((path: file, width: size.width, height: size.height));
    }
    return result;
  } catch (_) {
    return null;
  }
}
