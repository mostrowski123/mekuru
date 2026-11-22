import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/data/services/manga_cache_store.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('manga_cache_store_');
    path = p.join(dir.path, mangaPagesCacheFileName);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('a manga whose page data is gone says so', () async {
    await expectLater(
      MangaCacheStore.read(path),
      throwsA(MangaPagesUnavailable.pagesMissing),
    );
    await expectLater(
      MangaCacheStore.readEncoded(path),
      throwsA(MangaPagesUnavailable.pagesMissing),
    );
  });

  test('page data that is there is read as it is stored', () async {
    final json = jsonEncode(
      const MokuroBook(title: 'Manga', imageDirPath: '', pages: []).toJson(),
    );
    File(path).writeAsStringSync(json);

    expect(await MangaCacheStore.readEncoded(path), json);
    expect((await MangaCacheStore.read(path)).title, 'Manga');
  });

  test('page data that cannot be parsed is not called missing', () async {
    File(path).writeAsStringSync('{"title": "Manga", "pages": ');

    await expectLater(
      MangaCacheStore.read(path),
      throwsA(isNot(MangaPagesUnavailable.pagesMissing)),
    );
  });
}
