import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mekuru/features/sync/data/models/remote_models.dart';
import 'package:mekuru/features/sync/data/services/kavita_client.dart';
import 'package:mekuru/features/sync/data/services/server_client.dart';

void main() {
  const series = RemoteSeries(
    id: '7',
    libraryId: '2',
    title: '銀河英雄伝説',
    bookCount: 0,
  );

  // Response(String) encodes latin1 and rejects Japanese — always answer
  // with UTF-8 bytes, as a real server does.
  http.Response ok(Object json) =>
      http.Response.bytes(utf8.encode(jsonEncode(json)), 200);

  http.Response authOk() => ok({'token': 'jwt-1'});

  KavitaClient clientWith(
    Future<http.Response> Function(http.Request) handler,
  ) => KavitaClient(
    baseUrl: 'http://kavita.local:5000',
    getSecret: () => 'my-api-key',
    httpClient: MockClient(handler),
  );

  test('authenticates once, then sends the JWT as Bearer', () async {
    final requests = <http.Request>[];
    final client = clientWith((request) async {
      requests.add(request);
      if (request.url.path == '/api/Plugin/authenticate') {
        return authOk();
      }
      return ok([
        {'id': 2, 'name': 'Books'},
      ]);
    });

    final libraries = await client.listLibraries();
    await client.listLibraries();

    expect(libraries.single.id, '2');
    final authCalls = requests
        .where((r) => r.url.path == '/api/Plugin/authenticate')
        .toList();
    expect(authCalls, hasLength(1));
    expect(authCalls.single.url.queryParameters['apiKey'], 'my-api-key');
    expect(authCalls.single.url.queryParameters['pluginName'], 'Mekuru');
    final apiCalls = requests.where(
      (r) => r.url.path == '/api/Library/libraries',
    );
    expect(apiCalls.length, 2);
    for (final call in apiCalls) {
      expect(call.headers['Authorization'], 'Bearer jwt-1');
    }
  });

  test('re-authenticates once on 401 and retries', () async {
    var tokenCounter = 0;
    final client = clientWith((request) async {
      if (request.url.path == '/api/Plugin/authenticate') {
        tokenCounter++;
        return ok({'token': 'jwt-$tokenCounter'});
      }
      if (request.headers['Authorization'] == 'Bearer jwt-1') {
        return http.Response('expired', 401);
      }
      return ok([]);
    });

    await client.listLibraries();

    expect(tokenCounter, 2);
  });

  test('listSeries posts a Libraries-contains filter and paginates', () async {
    final seriesRequests = <http.Request>[];
    final client = clientWith((request) async {
      if (request.url.path == '/api/Plugin/authenticate') {
        return authOk();
      }
      seriesRequests.add(request);
      final page = request.url.queryParameters['PageNumber'];
      if (page == '1') {
        // A full page forces a second request.
        return ok([
          for (var i = 0; i < 100; i++) {'id': i, 'name': 'series $i'},
        ]);
      }
      return ok([
        {'id': 100, 'name': 'last'},
      ]);
    });

    final result = await client.listSeries('2');

    expect(result, hasLength(101));
    expect(seriesRequests, hasLength(2));
    final body = jsonDecode(seriesRequests.first.body) as Map<String, dynamic>;
    expect(body['statements'], [
      {'comparison': 5, 'field': 19, 'value': '2'},
    ]);
  });

  test('listSeries with search filters to the library', () async {
    final client = clientWith((request) async {
      if (request.url.path == '/api/Plugin/authenticate') {
        return authOk();
      }
      expect(request.url.path, '/api/Search/search');
      return ok({
        'series': [
          {'seriesId': 7, 'libraryId': 2, 'name': '銀河英雄伝説'},
          {'seriesId': 9, 'libraryId': 3, 'name': 'other library'},
        ],
      });
    });

    final result = await client.listSeries('2', search: '銀河');

    expect(result, hasLength(1));
    expect(result.single.id, '7');
    expect(result.single.title, '銀河英雄伝説');
  });

  test('listBooks flattens volumes, skips PDFs, carries pages', () async {
    final client = clientWith((request) async {
      if (request.url.path == '/api/Plugin/authenticate') {
        return authOk();
      }
      return ok([
        {
          'id': 11,
          'name': 'Volume 1',
          'chapters': [
            {'id': 101, 'format': 3, 'pages': 210, 'titleName': ''},
          ],
        },
        {
          'id': 12,
          'name': 'Extras',
          'chapters': [
            {'id': 102, 'format': 4, 'pages': 5, 'titleName': 'PDF Extra'},
            {'id': 103, 'format': 1, 'pages': 42, 'titleName': 'Omake'},
          ],
        },
      ]);
    });

    final books = await client.listBooks(series);

    expect(books, hasLength(2));
    expect(books[0].ids, {
      'chapterId': '101',
      'volumeId': '11',
      'seriesId': '7',
      'libraryId': '2',
      'pages': '210',
      'epub': 'true',
    });
    expect(books[0].format, RemoteBookFormat.epub);
    expect(books[0].title, 'Volume 1');
    expect(books[1].ids['chapterId'], '103');
    expect(books[1].title, 'Omake');
    expect(books[1].format, RemoteBookFormat.imageArchive);
  });

  test('pullProgress maps pageNum and completion', () async {
    final client = clientWith((request) async {
      if (request.url.path == '/api/Plugin/authenticate') {
        return authOk();
      }
      return ok({'pageNum': 210, 'lastModifiedUtc': '2026-08-30T12:00:00Z'});
    });

    final progress = await client.pullProgress({
      'chapterId': '101',
      'pages': '210',
    });

    expect(progress, isNotNull);
    expect(progress!.page, 210);
    expect(progress.completed, isTrue);
    expect(progress.totalProgression, 1.0);
    expect(progress.lastModified, DateTime.parse('2026-08-30T12:00:00Z'));
  });

  test('pullProgress returns null when the server has none', () async {
    final client = clientWith((request) async {
      if (request.url.path == '/api/Plugin/authenticate') {
        return authOk();
      }
      return ok({'pageNum': 0});
    });

    expect(await client.pullProgress({'chapterId': '101'}), isNull);
  });

  test('pushProgress converts EPUB totalProgression to pageNum', () async {
    late http.Request seen;
    final client = clientWith((request) async {
      if (request.url.path == '/api/Plugin/authenticate') {
        return authOk();
      }
      seen = request;
      return http.Response('', 200);
    });

    await client.pushProgress({
      'chapterId': '101',
      'volumeId': '11',
      'seriesId': '7',
      'libraryId': '2',
      'pages': '210',
      'epub': 'true',
    }, const RemoteProgress(totalProgression: 0.5));

    expect(seen.url.path, '/api/Reader/progress');
    final body = jsonDecode(seen.body) as Map<String, dynamic>;
    expect(body['pageNum'], 105);
    expect(body['chapterId'], 101);
    expect(body['volumeId'], 11);
    expect(body['seriesId'], 7);
    expect(body['libraryId'], 2);
    expect(body['bookScrollId'], isNull);
  });

  test('a bad API key surfaces as SyncException', () async {
    final client = clientWith((request) async => http.Response('denied', 401));

    expect(
      () => client.testConnection(),
      throwsA(
        isA<SyncException>().having((e) => e.statusCode, 'statusCode', 401),
      ),
    );
  });
}
