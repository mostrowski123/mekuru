// ignore_for_file: discarded_futures
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/features/manga/data/services/model_download.dart';
import 'package:mekuru/shared/downloads/download.dart';

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

    await runDownload<void>(
      DownloadSpec(
        DownloadKind.ndlTextModel,
        id: dir.path,
        dir: dir.path,
        parts: [
          (
            name: 'NDLmoji.yaml',
            url: 'http://127.0.0.1:${server.port}/NDLmoji.yaml',
            bytes: body.length,
            sha256: sha256.convert(body).toString(),
          ),
        ],
      ),
      NetworkConsent.mobileData,
    );

    expect(await modelFilesInstalled(dir), isTrue);
    expect(await File('${dir.path}/NDLmoji.yaml').readAsBytes(), body);
  });

  test('a second download of the same folder joins the first', () async {
    final body = List<int>.generate(64 * 1024, (i) => i % 251);
    var requests = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) {
      requests++;
      request.response.headers.contentLength = body.length;
      request.response.add(body);
      request.response.close();
    });
    final dir = await Directory.systemTemp.createTemp('model_download_test');
    addTearDown(() => dir.delete(recursive: true));
    final files = <ModelFile>[
      (
        name: 'model.onnx',
        url: 'http://127.0.0.1:${server.port}/model.onnx',
        bytes: body.length,
        sha256: sha256.convert(body).toString(),
      ),
    ];

    final spec = DownloadSpec(
      DownloadKind.ndlTextModel,
      id: dir.path,
      dir: dir.path,
      parts: files,
    );
    await Future.wait([
      runDownload<void>(spec, NetworkConsent.mobileData),
      runDownload<void>(spec, NetworkConsent.mobileData),
    ]);

    expect(requests, 1);
    expect(await File('${dir.path}/model.onnx').readAsBytes(), body);
  });
}
