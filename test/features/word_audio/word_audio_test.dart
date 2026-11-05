import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/data/services/model_download.dart';
import 'package:mekuru/features/word_audio/data/services/word_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../shared/fake_path_provider.dart';

const _clip = 'f84aff2662b3f2f2';

void main() {
  late Directory root;
  late HttpServer server;
  late WordAudio audio;
  late Uint8List indexBytes;
  var clipRequests = 0;
  var failClips = false;
  Completer<void>? clipGate;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('word_audio');
    final support = Directory(p.join(root.path, 'support'))..createSync();
    PathProviderPlatform.instance = FakePathProviderPlatform(support.path);

    final indexPath = p.join(root.path, 'index.sqlite');
    final db = sqlite3.open(indexPath);
    db.execute('''
      CREATE TABLE pair(
        expression TEXT NOT NULL,
        reading TEXT NOT NULL,
        id BLOB NOT NULL,
        score INTEGER NOT NULL,
        PRIMARY KEY (expression, reading)
      ) WITHOUT ROWID;
      CREATE INDEX pair_reading ON pair(reading);
    ''');
    db.execute(
      "INSERT INTO pair VALUES ('学校', 'がっこう', x'f84aff2662b3f2f2', 1)",
    );
    db.close();
    indexBytes = File(indexPath).readAsBytesSync();

    clipRequests = 0;
    failClips = false;
    clipGate = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final response = request.response;
      if (request.uri.path == '/v1/index.sqlite') {
        response.add(indexBytes);
      } else if (request.uri.path == '/v1/clips/f8/$_clip.mp3') {
        clipRequests++;
        await clipGate?.future;
        if (failClips) {
          response.statusCode = HttpStatus.notFound;
        } else {
          response.add(const [1, 2, 3]);
        }
      } else {
        response.statusCode = HttpStatus.notFound;
      }
      await response.close();
    });
    final base = 'http://127.0.0.1:${server.port}/v1';
    final ModelFile indexFile = (
      name: 'index.sqlite',
      url: '$base/index.sqlite',
      bytes: indexBytes.length,
      sha256: sha256.convert(indexBytes).toString(),
    );
    audio = WordAudio(base: base, indexFile: indexFile);
  });

  tearDown(() async {
    audio.dispose();
    await server.close(force: true);
    root.deleteSync(recursive: true);
  });

  group('a word list from an older pin', () {
    late String oldClip;

    setUp(() async {
      await audio.download();
      oldClip = (await audio.clipFile(_clip)).path;
      File(oldClip).writeAsBytesSync(const [9]);
      audio.dispose();
    });

    WordAudio relaunched() =>
        WordAudio(base: audio.base, indexFile: audio.indexFile);

    test('goes with its clips, and the new one downloads', () async {
      final dir = await WordAudio.storageDir();
      File(
        p.join(dir, audio.indexFile.name),
      ).renameSync(p.join(dir, 'word_audio_index_2026-07-27.sqlite'));
      final next = relaunched();
      addTearDown(next.dispose);

      expect(await next.installed, isFalse);
      expect(await next.clipFor('学校', 'がっこう'), isNull);
      expect(Directory(dir).listSync(), isEmpty);
      expect(File(oldClip).existsSync(), isFalse);

      await next.download();
      expect(await next.clipFor('学校', 'がっこう'), _clip);
      expect(File((await next.clipFile(_clip)).path).readAsBytesSync(), [
        1,
        2,
        3,
      ]);
    });

    test('leaves the current list and its clips alone', () async {
      final next = relaunched();
      addTearDown(next.dispose);

      expect(await next.installed, isTrue);
      expect(await next.clipFor('学校', 'がっこう'), _clip);
      expect((await next.clipFile(_clip)).source, 'cache');
    });
  });

  test('no clip until the word list is installed, then it finds one', () async {
    expect(await audio.installed, isFalse);
    expect(await audio.clipFor('学校', 'がっこう'), isNull);

    await audio.download();

    expect(await audio.installed, isTrue);
    expect(await audio.clipFor('学校', 'がっこう'), _clip);
  });

  test('a clip is fetched once, then comes from the cache', () async {
    final first = await audio.clipFile(_clip);
    expect(first.source, 'network');
    expect(File(first.path).readAsBytesSync(), [1, 2, 3]);

    final second = await audio.clipFile(_clip);
    expect(second.source, 'cache');
    expect(second.path, first.path);
    expect(clipRequests, 1);
  });

  test('two calls while fetching share one request', () async {
    clipGate = Completer<void>();
    final calls = [audio.clipFile(_clip), audio.clipFile(_clip)];
    await Future<void>.delayed(const Duration(milliseconds: 50));
    clipGate!.complete();

    final clips = await Future.wait(calls);

    expect(clips.map((c) => c.path).toSet(), hasLength(1));
    expect(clipRequests, 1);
  });

  test(
    'a failed fetch leaves nothing, and the next try fetches again',
    () async {
      failClips = true;
      await expectLater(audio.clipFile(_clip), throwsA(isA<HttpException>()));

      failClips = false;
      expect((await audio.clipFile(_clip)).source, 'network');
      expect(clipRequests, 2);
    },
  );

  test('remove deletes the word list and the fetched clips', () async {
    await audio.download();
    await audio.clipFor('学校', 'がっこう');
    final clip = await audio.clipFile(_clip);

    await audio.remove();

    expect(await audio.installed, isFalse);
    expect(await audio.clipFor('学校', 'がっこう'), isNull);
    expect(File(clip.path).existsSync(), isFalse);
  });

  test('the clip address is what the bucket holds', () {
    expect(audio.clipUrl(_clip), endsWith('/v1/clips/f8/$_clip.mp3'));
  });
}
