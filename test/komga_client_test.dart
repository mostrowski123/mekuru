import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mekuru/features/sync/data/models/remote_models.dart';
import 'package:mekuru/features/sync/data/services/komga_client.dart';
import 'package:mekuru/features/sync/data/services/server_client.dart';

void main() {
  const series = RemoteSeries(
    id: 's1',
    libraryId: 'lib1',
    title: 'よつばと！',
    bookCount: 2,
  );

  KomgaClient clientWith(
    Future<http.Response> Function(http.Request) handler, {
    String secret = 'api-key-123',
  }) => KomgaClient(
    baseUrl: 'http://komga.local:25600/',
    getSecret: () => secret,
    httpClient: MockClient(handler),
  );

  // Response(String) encodes latin1 and rejects Japanese — always answer
  // with UTF-8 bytes, as a real server does.
  http.Response ok(Object json) =>
      http.Response.bytes(utf8.encode(jsonEncode(json)), 200);

  test('sends X-API-Key header and strips trailing base-url slash', () async {
    late http.Request seen;
    final client = clientWith((request) async {
      seen = request;
      return ok([
        {'id': 'lib1', 'name': 'Manga'},
      ]);
    });

    final libraries = await client.listLibraries();

    expect(seen.url.toString(), 'http://komga.local:25600/api/v1/libraries');
    expect(seen.headers['X-API-Key'], 'api-key-123');
    expect(libraries.single.id, 'lib1');
    expect(libraries.single.name, 'Manga');
  });

  test('a secret containing a colon selects HTTP Basic auth', () async {
    late http.Request seen;
    final client = clientWith((request) async {
      seen = request;
      return ok([]);
    }, secret: 'user:pass');

    await client.listLibraries();

    expect(
      seen.headers['Authorization'],
      'Basic ${base64Encode(utf8.encode('user:pass'))}',
    );
    expect(seen.headers.containsKey('X-API-Key'), isFalse);
  });

  test('listSeries follows pagination and passes search', () async {
    final requests = <http.Request>[];
    final client = clientWith((request) async {
      requests.add(request);
      final page = request.url.queryParameters['page'];
      if (page == '0') {
        return ok({
          'content': [
            {
              'id': 's1',
              'name': 'raw',
              'booksCount': 2,
              'metadata': {'title': 'よつばと！'},
            },
          ],
          'last': false,
        });
      }
      return ok({
        'content': [
          {'id': 's2', 'name': 'No Meta', 'booksCount': 1},
        ],
        'last': true,
      });
    });

    final result = await client.listSeries('lib1', search: 'よつば');

    expect(result, hasLength(2));
    expect(result[0].title, 'よつばと！');
    expect(result[1].title, 'No Meta');
    expect(requests[0].url.queryParameters['library_id'], 'lib1');
    expect(requests[0].url.queryParameters['search'], 'よつば');
    expect(requests, hasLength(2));
  });

  test('listBooks skips PDFs and flags EPUBs', () async {
    final client = clientWith((request) async {
      return ok({
        'content': [
          {
            'id': 'b1',
            'name': 'vol1',
            'media': {'mediaProfile': 'DIVINA', 'pagesCount': 180},
          },
          {
            'id': 'b2',
            'name': 'novel',
            'media': {'mediaProfile': 'EPUB', 'pagesCount': 0},
          },
          {
            'id': 'b3',
            'name': 'scan.pdf',
            'media': {'mediaProfile': 'PDF', 'pagesCount': 10},
          },
        ],
        'last': true,
      });
    });

    final books = await client.listBooks(series);

    expect(books, hasLength(2));
    expect(books[0].ids, {'bookId': 'b1', 'seriesId': 's1'});
    expect(books[0].format, RemoteBookFormat.imageArchive);
    expect(books[0].fileExtension, '.cbz');
    expect(books[0].pageCount, 180);
    expect(books[1].ids['epub'], 'true');
    expect(books[1].format, RemoteBookFormat.epub);
    expect(books[1].fileExtension, '.epub');
  });

  test('pullProgress converts 1-based pages and merges R2 locator', () async {
    final client = clientWith((request) async {
      if (request.url.path.endsWith('/progression')) {
        return ok({
          'modified': '2026-09-01T10:00:00Z',
          'locator': {
            'href': 'OEBPS/ch3.xhtml',
            'locations': {'progression': 0.25, 'totalProgression': 0.4},
          },
        });
      }
      return ok({
        'id': 'b2',
        'readProgress': {
          'page': 3,
          'completed': false,
          'lastModified': '2026-09-01T09:00:00Z',
        },
      });
    });

    final progress = await client.pullProgress({
      'bookId': 'b2',
      'seriesId': 's1',
      'epub': 'true',
    });

    expect(progress, isNotNull);
    expect(progress!.page, 2);
    expect(progress.href, 'OEBPS/ch3.xhtml');
    expect(progress.progression, 0.25);
    expect(progress.totalProgression, 0.4);
    // The locator timestamp wins when present.
    expect(progress.lastModified, DateTime.parse('2026-09-01T10:00:00Z'));
  });

  test('pullProgress returns null for a book with no progress', () async {
    final client = clientWith((request) async => ok({'id': 'b1'}));

    expect(await client.pullProgress({'bookId': 'b1'}), isNull);
  });

  test('pushProgress PATCHes 1-based page for manga', () async {
    late http.Request seen;
    final client = clientWith((request) async {
      seen = request;
      return http.Response('', 204);
    });

    await client.pushProgress({
      'bookId': 'b1',
      'seriesId': 's1',
    }, const RemoteProgress(page: 41, completed: false));

    expect(seen.method, 'PATCH');
    expect(seen.url.path, '/api/v1/books/b1/read-progress');
    expect(jsonDecode(seen.body), {'page': 42, 'completed': false});
  });

  test('pushProgress PUTs an R2 locator for EPUBs', () async {
    final requests = <http.Request>[];
    final client = clientWith((request) async {
      requests.add(request);
      return http.Response('', 204);
    });

    await client.pushProgress(
      {'bookId': 'b2', 'epub': 'true'},
      const RemoteProgress(
        href: 'OEBPS/ch3.xhtml',
        progression: 0.25,
        totalProgression: 0.4,
        completed: true,
      ),
    );

    expect(requests, hasLength(2));
    expect(requests[0].method, 'PUT');
    expect(requests[0].url.path, '/api/v1/books/b2/progression');
    final body = jsonDecode(requests[0].body) as Map<String, dynamic>;
    final locator = body['locator'] as Map<String, dynamic>;
    expect(locator['href'], 'OEBPS/ch3.xhtml');
    expect(locator['locations'], {
      'progression': 0.25,
      'totalProgression': 0.4,
    });
    // completed additionally marks the book read.
    expect(requests[1].method, 'PATCH');
    expect(jsonDecode(requests[1].body), {'completed': true});
  });

  test('non-2xx responses become SyncException with the status', () async {
    final client = clientWith((request) async => http.Response('nope', 401));

    expect(
      () => client.listLibraries(),
      throwsA(
        isA<SyncException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.isAuthFailure, 'isAuthFailure', true),
      ),
    );
  });
}
