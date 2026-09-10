import 'dart:convert';
import 'dart:io';

import 'package:local_manga_ocr/local_manga_ocr.dart';
import '../models/mokuro_models.dart';
import '../../../../core/utils/atomic_file.dart';

/// All async calculations merge into the current cache. Android's native store
/// serializes writes from UI engines, WorkManager, and local OCR.
class MangaCacheStore {
  static Future<MokuroBook> read(String path) async => MokuroBook.fromJson(
    jsonDecode(await File(path).readAsString()) as Map<String, dynamic>,
  );
  static bool _equal(Object? a, Object? b) {
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.keys.every((key) => b.containsKey(key) && _equal(a[key], b[key]));
    }
    if (a is List && b is List) {
      return a.length == b.length &&
          List.generate(a.length, (i) => i).every((i) => _equal(a[i], b[i]));
    }
    return a == b;
  }

  static bool _sameRecognition(List old, List next) {
    Map withoutWords(Object? block) => Map.from(block as Map)..remove('words');
    return _equal(
      old.map(withoutWords).toList(),
      next.map(withoutWords).toList(),
    );
  }

  static Future<String> merge(
    File file, {
    required String before,
    required String after,
  }) async {
    if (LocalMangaOcr.available) {
      return (await LocalMangaOcr.channel.invokeMethod<String>('mergeCache', {
        'path': file.path,
        'before': before,
        'after': after,
      }))!;
    }
    // Desktop has no native OCR writer. Keep compare-and-merge semantics for
    // segmentation and cropping, and make the same policy unit-testable.
    final current = await file.readAsString();
    final result = mergeJson(
      jsonDecode(current) as Map<String, dynamic>,
      jsonDecode(before) as Map<String, dynamic>,
      jsonDecode(after) as Map<String, dynamic>,
    );
    final encoded = jsonEncode(result);
    await writeStringAtomic(file, encoded);
    return encoded;
  }

  static Map<String, dynamic> mergeJson(
    Map<String, dynamic> current,
    Map<String, dynamic> before,
    Map<String, dynamic> after,
  ) {
    if (before['ocrGeneration'] != null &&
        current['ocrGeneration'] != before['ocrGeneration']) {
      throw StateError('book_changed');
    }
    final oldPages = before['pages'] as List;
    final nextPages = after['pages'] as List;
    final pages = current['pages'] as List;
    if (pages.length != oldPages.length || pages.length != nextPages.length) {
      throw StateError('book_changed');
    }
    final merged = <Map<String, dynamic>>[];
    for (var i = 0; i < pages.length; i++) {
      final page = Map<String, dynamic>.from(pages[i] as Map);
      final old = oldPages[i] as Map;
      final next = nextPages[i] as Map;
      if (page['imageFileName'] != old['imageFileName']) {
        throw StateError('book_changed');
      }
      final sameOcr = _equal(page['ocr'], old['ocr']);
      final derivedOnly = _sameRecognition(
        old['blocks'] as List,
        next['blocks'] as List,
      );
      for (final key in {...old.keys, ...next.keys}) {
        if (const {
          'pageIndex',
          'imageFileName',
          'imgWidth',
          'imgHeight',
          'ocr',
        }.contains(key)) {
          continue;
        }
        if (_equal(old[key], next[key])) {
          continue;
        }
        if (const {'blocks', 'segmentationDictionary'}.contains(key) &&
            (!sameOcr || !derivedOnly)) {
          continue;
        }
        if (!_equal(page[key], old[key])) {
          continue;
        }
        if (next.containsKey(key)) {
          page[key as String] = next[key];
        } else {
          page.remove(key);
        }
      }
      merged.add(page);
    }
    return {
      ...current,
      'pages': merged,
      if (before['autoCropVersion'] != after['autoCropVersion'])
        'autoCropVersion': after['autoCropVersion'],
    };
  }

  static Future<void> reset(File file, int bookId, String after) async {
    if (LocalMangaOcr.available) {
      await LocalMangaOcr.channel.invokeMethod('resetCache', {
        'path': file.path,
        'bookId': bookId,
        'after': after,
      });
    } else {
      await writeStringAtomic(file, after);
    }
  }
}
