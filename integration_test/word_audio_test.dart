import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/manga/data/services/model_download.dart';
import 'package:mekuru/features/word_audio/data/services/word_audio.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../test/shared/word_audio_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('downloads the word list and a clip, then really plays it', (
    tester,
  ) async {
    const clip = 'f84aff2662b3f2f2';
    final temp = await Directory.systemTemp.createTemp('word_audio_');
    final indexPath = p.join(temp.path, 'index.sqlite');
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
    db.execute("INSERT INTO pair VALUES ('学校', 'がっこう', x'$clip', 1)");
    db.close();
    final indexBytes = await File(indexPath).readAsBytes();

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final response = request.response;
      if (request.uri.path == '/v1/index.sqlite') {
        response.add(indexBytes);
      } else if (request.uri.path == '/v1/clips/f8/$clip.mp3') {
        response.add(base64Decode(silentClipBase64));
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
    final audio = WordAudio(base: base, indexFile: indexFile);
    addTearDown(() async {
      await audio.remove();
      audio.dispose();
      await server.close(force: true);
      await temp.delete(recursive: true);
    });

    await audio.remove();
    expect(await audio.clipFor('学校', 'がっこう'), isNull);

    await audio.download();
    final found = await audio.clipFor('学校', 'がっこう');
    expect(found, clip);

    // Throws when the platform's player can't take the file.
    await audio.play(found!);
    expect((await audio.clipFile(clip)).source, 'cache');

    // A damaged file is reported and goes, so the next try fetches it again.
    await File((await audio.clipFile(clip)).path).writeAsString('not audio');
    await expectLater(
      audio.play(clip),
      throwsA(isA<WordAudioPlaybackException>()),
    );
    expect((await audio.clipFile(clip)).source, 'network');
  });
}
