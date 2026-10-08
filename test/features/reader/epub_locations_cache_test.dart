import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/reader/data/services/epub_locations_cache.dart';
import 'package:path/path.dart' as p;

void main() {
  const locations = '["epubcfi(/6/2!/4/2/1:0)","epubcfi(/6/2!/4/2/1:1600)"]';
  late Directory dir;
  late String epub;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('epub_locations_');
    epub = p.join(dir.path, 'book.epub');
    await File(epub).writeAsBytes(List.filled(64, 1));
  });

  tearDown(() => dir.delete(recursive: true));

  File cache() => File(p.join(dir.path, 'locations.json'));

  test('saved locations come back for the same book', () async {
    expect(await EpubLocationsCache.read(epub), isNull);

    await EpubLocationsCache.write(epub, locations);

    expect(await EpubLocationsCache.read(epub), locations);
  });

  test('a changed EPUB file has them generated again', () async {
    await EpubLocationsCache.write(epub, locations);
    await File(epub).writeAsBytes(List.filled(65, 1));
    expect(await EpubLocationsCache.read(epub), isNull, reason: 'size');

    await EpubLocationsCache.write(epub, locations);
    await File(epub).setLastModified(DateTime(2020));
    expect(await EpubLocationsCache.read(epub), isNull, reason: 'mtime');
  });

  test(
    'a corrupt file reads as none and is replaced by the next save',
    () async {
      await cache().writeAsString('{"version": 1, "locati');
      expect(await EpubLocationsCache.read(epub), isNull);

      // What the bridge sends is checked before it is saved.
      await EpubLocationsCache.write(epub, 'not locations');
      expect(await cache().readAsString(), '{"version": 1, "locati');

      await EpubLocationsCache.write(epub, locations);
      expect(await EpubLocationsCache.read(epub), locations);
    },
  );

  test(
    'locations saved before a cache version bump are generated again',
    () async {
      await EpubLocationsCache.write(epub, locations);
      final saved = jsonDecode(await cache().readAsString()) as Map;
      await cache().writeAsString(
        jsonEncode({...saved, 'version': EpubLocationsCache.version - 1}),
      );

      expect(await EpubLocationsCache.read(epub), isNull);
    },
  );
}
