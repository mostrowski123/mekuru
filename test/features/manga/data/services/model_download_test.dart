import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/data/services/model_download.dart';

void main() {
  test('a file the server would gzip arrives as pinned', () async {
    // Like raw.githubusercontent.com: text is gzipped for any client that
    // accepts it, and Content-Length is then the compressed size.
    final body = utf8.encode('charset_train: "${'あいう' * 2000}"\n');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) {
      final gzipped = (request.headers.value('accept-encoding') ?? '').contains(
        'gzip',
      );
      final out = gzipped ? gzip.encode(body) : body;
      request.response.headers.contentLength = out.length;
      if (gzipped) request.response.headers.set('content-encoding', 'gzip');
      request.response.add(out);
      request.response.close();
    });
    final dir = await Directory.systemTemp.createTemp('model_download_test');
    addTearDown(() => dir.delete(recursive: true));

    await downloadModelFiles(dir, [
      (
        name: 'NDLmoji.yaml',
        url: 'http://127.0.0.1:${server.port}/NDLmoji.yaml',
        bytes: body.length,
        sha256: sha256.convert(body).toString(),
      ),
    ]);

    expect(await modelFilesInstalled(dir), isTrue);
    expect(await File('${dir.path}/NDLmoji.yaml').readAsBytes(), body);
  });
}
