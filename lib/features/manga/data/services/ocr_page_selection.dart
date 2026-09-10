import 'package:local_manga_ocr/local_manga_ocr.dart';
import '../models/mokuro_models.dart';

List<int> selectOcrPages(
  MokuroBook book, {
  int? pageIndex,
  OcrExistingPolicy policy = OcrExistingPolicy.missingOnly,
}) {
  if (pageIndex != null && (pageIndex < 0 || pageIndex >= book.pages.length)) {
    throw RangeError.index(pageIndex, book.pages);
  }
  return [
    for (var index = 0; index < book.pages.length; index++)
      if ((pageIndex == null || index == pageIndex) &&
          (policy == OcrExistingPolicy.replace ||
              !book.pages[index].hasOcr(book)))
        index,
  ];
}
