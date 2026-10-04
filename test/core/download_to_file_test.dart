import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/services/download_to_file.dart';
import 'package:path/path.dart' as p;

/// Tests [downloadToFile] and [withDownloadedFile] against a loopback HTTP
/// server so the redirect, progress, and error paths run through the real
/// dart:io HttpClient.
void main() {
  late Directory tempDir;
  late HttpServer server;

  // Large enough to arrive in more than one socket chunk.
  final payload = List<int>.generate(64 * 1024 + 17, (i) => i % 251);

  String urlFor(String path) => 'http://127.0.0.1:${server.port}$path';

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('download_to_file_test_');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final path = request.uri.path;
      final response = request.response;
      switch (path) {
        case '/asset':
          response.contentLength = payload.length;
          response.add(payload);
        case '/redirect':
          await response.redirect(
            Uri.parse(urlFor('/redirect2')),
            status: HttpStatus.found,
          );
          return;
        case '/redirect2':
          await response.redirect(
            Uri.parse(urlFor('/asset')),
            status: HttpStatus.found,
          );
          return;
        case '/loop':
          await response.redirect(
            Uri.parse(urlFor('/loop')),
            status: HttpStatus.found,
          );
          return;
        case '/chunked':
          response.add(payload);
        case '/broken':
          // Promise more bytes than are sent: closing below contentLength
          // aborts the connection, so the client fails mid-body.
          response.contentLength = payload.length * 2;
          response.add(payload);
          try {
            await response.close();
          } on HttpException {
            // Expected: content size below the declared contentLength.
          }
          return;
        default:
          response.statusCode = HttpStatus.notFound;
      }
      await response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('downloadToFile', () {
    test('writes the response body to the destination file', () async {
      final destination = p.join(tempDir.path, 'asset.zip');

      await downloadToFile(urlFor('/asset'), destination);

      expect(File(destination).readAsBytesSync(), payload);
    });

    test('follows redirects to the final asset', () async {
      final destination = p.join(tempDir.path, 'asset.zip');

      await downloadToFile(urlFor('/redirect'), destination);

      expect(File(destination).readAsBytesSync(), payload);
    });

    test(
      'reports increasing progress ending at 1.0 when length is known',
      () async {
        final destination = p.join(tempDir.path, 'asset.zip');
        final progress = <double>[];

        await downloadToFile(
          urlFor('/asset'),
          destination,
          onProgress: progress.add,
        );

        expect(progress, isNotEmpty);
        expect(progress, everyElement(greaterThan(0)));
        expect(progress.last, 1.0);
        for (var i = 1; i < progress.length; i++) {
          expect(progress[i], greaterThan(progress[i - 1]));
        }
      },
    );

    test('skips progress but still downloads when length is unknown', () async {
      final destination = p.join(tempDir.path, 'asset.zip');
      final progress = <double>[];

      await downloadToFile(
        urlFor('/chunked'),
        destination,
        onProgress: progress.add,
      );

      expect(progress, isEmpty);
      expect(File(destination).readAsBytesSync(), payload);
    });

    test('throws HttpException on a non-200 response', () async {
      final destination = p.join(tempDir.path, 'asset.zip');

      await expectLater(
        downloadToFile(urlFor('/missing'), destination),
        throwsA(isA<HttpException>()),
      );
      expect(File(destination).existsSync(), isFalse);
    });

    test('throws HttpException when the redirect limit is exceeded', () async {
      final destination = p.join(tempDir.path, 'asset.zip');

      await expectLater(
        downloadToFile(urlFor('/loop'), destination),
        throwsA(isA<HttpException>()),
      );
    });

    test(
      'deletes the partial file when the connection drops mid-body',
      () async {
        final destination = p.join(tempDir.path, 'asset.zip');

        await expectLater(
          downloadToFile(urlFor('/broken'), destination),
          throwsA(isA<HttpException>()),
        );
        expect(File(destination).existsSync(), isFalse);
      },
    );
  });

  group('withDownloadedFile', () {
    test(
      'passes the downloaded file to use and deletes it afterwards',
      () async {
        final destination = p.join(tempDir.path, 'asset.zip');

        final length = await withDownloadedFile(
          urlFor('/asset'),
          destination,
          use: (path) async {
            expect(path, destination);
            return File(path).lengthSync();
          },
        );

        expect(length, payload.length);
        expect(File(destination).existsSync(), isFalse);
      },
    );

    test('deletes the file when use throws', () async {
      final destination = p.join(tempDir.path, 'asset.zip');

      await expectLater(
        withDownloadedFile<void>(
          urlFor('/asset'),
          destination,
          use: (_) async => throw StateError('use failed'),
        ),
        throwsStateError,
      );
      expect(File(destination).existsSync(), isFalse);
    });

    test('skips use when the download fails', () async {
      final destination = p.join(tempDir.path, 'asset.zip');
      var useCalled = false;

      await expectLater(
        withDownloadedFile<void>(
          urlFor('/missing'),
          destination,
          use: (_) async => useCalled = true,
        ),
        throwsA(isA<HttpException>()),
      );
      expect(useCalled, isFalse);
      expect(File(destination).existsSync(), isFalse);
    });
  });
}
