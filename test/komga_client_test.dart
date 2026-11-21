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
  http.Response ok(Object json, [int status = 200]) =>
      http.Response.bytes(utf8.encode(jsonEncode(json)), status);

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

  test('listBooks maps archives, EPUBs and PDFs', () async {
    final client = clientWith((request) async {
      return ok({
        'content': [
          {
            'id': 'b1',
            'name': 'vol1',
            'sizeBytes': 52428800,
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

    expect(books, hasLength(3));
    expect(books[0].ids, {'bookId': 'b1', 'seriesId': 's1'});
    expect(books[0].format, RemoteBookFormat.imageArchive);
    expect(books[0].fileExtension, '.cbz');
    expect(books[0].pageCount, 180);
    // What a download checks the free space against.
    expect(books[0].sizeBytes, 52428800);
    expect(books[1].sizeBytes, isNull);
    expect(books[1].ids['epub'], 'true');
    expect(books[1].format, RemoteBookFormat.epub);
    expect(books[1].fileExtension, '.epub');
    expect(books[2].ids, {'bookId': 'b3', 'seriesId': 's1'});
    expect(books[2].format, RemoteBookFormat.pdf);
    expect(books[2].fileExtension, '.pdf');
    expect(books[2].pageCount, 10);
  });

  test('pullProgress converts 1-based pages and merges R2 locator', () async {
    final client = clientWith((request) async {
      if (request.url.path.endsWith('/progression')) {
        // Served as a Readium media type: plain JSON is not acceptable.
        if (request.headers['Accept'] == 'application/json') {
          return http.Response('', 406);
        }
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

  test('pullProgress reads an EPUB with no progression record yet', () async {
    final client = clientWith(
      (request) async => request.url.path.endsWith('/progression')
          ? http.Response('', 204)
          : ok({'id': 'b2'}),
    );

    expect(await client.pullProgress({'bookId': 'b2', 'epub': 'true'}), isNull);
  });

  test(
    'pullProgress derives an EPUB fraction from page-only progress',
    () async {
      final client = clientWith((request) async {
        if (request.url.path.endsWith('/progression')) {
          return http.Response('', 404);
        }
        return ok({
          'id': 'b2',
          'media': {'pagesCount': 200},
          'readProgress': {
            'page': 50,
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

      expect(progress!.page, 49);
      expect(progress.totalProgression, closeTo(0.25, 0.001));
    },
  );

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

  test(
    'pushProgress PUTs the reader locator when the server lists no positions',
    () async {
      final requests = <http.Request>[];
      final client = clientWith((request) async {
        requests.add(request);
        return request.method == 'GET'
            ? http.Response('', 404)
            : http.Response('', 204);
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

      expect(requests, hasLength(3));
      expect(requests[0].url.path, '/api/v1/books/b2/positions');
      expect(requests[1].method, 'PUT');
      expect(requests[1].url.path, '/api/v1/books/b2/progression');
      final body = jsonDecode(requests[1].body) as Map<String, dynamic>;
      final locator = body['locator'] as Map<String, dynamic>;
      expect(locator['href'], 'OEBPS/ch3.xhtml');
      expect(locator['locations'], {
        'progression': 0.25,
        'totalProgression': 0.4,
      });
      // completed additionally marks the book read.
      expect(requests[2].method, 'PATCH');
      expect(jsonDecode(requests[2].body), {'completed': true});
    },
  );

  // Komga refuses a locator that is not in its own position list: an href
  // relative to the package file, or a progression past a chapter's last
  // position.
  group('EPUB progress on a Komga that lists positions', () {
    Map<String, dynamic> position(String href, double progression, int n) => {
      'href': href,
      'type': 'application/xhtml+xml',
      'locations': {
        'progression': progression,
        'position': n,
        'totalProgression': n / 6,
      },
    };

    // As Komga lists them: one per KB of a chapter, by zip-root path.
    final positions = [
      position('OEBPS/ch1.xhtml', 0, 1),
      position('OEBPS/ch1.xhtml', 0.5, 2),
      position('OEBPS/ch3.xhtml', 0, 3),
      position('OEBPS/ch3.xhtml', 0.25, 4),
      position('OEBPS/ch3.xhtml', 0.5, 5),
      position('OEBPS/ch3.xhtml', 0.75, 6),
    ];

    late List<Map<String, dynamic>> saved;
    late int positionRequests;

    http.Response refused(String message) =>
        ok({'status': 400, 'error': 'Bad Request', 'message': message}, 400);

    Future<http.Response> komga(http.Request request) async {
      if (request.url.path.endsWith('/positions')) {
        positionRequests++;
        // Served as a Readium media type: plain JSON is not acceptable.
        return request.headers['Accept'] == 'application/json'
            ? http.Response('', 406)
            : ok({'total': positions.length, 'positions': positions});
      }
      saved.add(
        (jsonDecode(request.body) as Map<String, dynamic>)['locator']
            as Map<String, dynamic>,
      );
      return http.Response('', 204);
    }

    setUp(() {
      saved = [];
      positionRequests = 0;
    });

    Future<void> push(KomgaClient client, RemoteProgress progress) =>
        client.pushProgress({'bookId': 'b2', 'epub': 'true'}, progress);

    test('a book whose package file sits in a folder is saved', () async {
      // The reader reports the chapter relative to the package file.
      await push(
        clientWith(komga),
        const RemoteProgress(
          href: 'ch3.xhtml',
          progression: 0.6,
          totalProgression: 0.8,
        ),
      );

      expect(saved.single, positions[4]);
    });

    test('the last pages of a chapter are saved', () async {
      await push(
        clientWith(komga),
        const RemoteProgress(
          href: 'ch3.xhtml',
          progression: 0.95,
          totalProgression: 0.99,
        ),
      );

      expect(saved.single, positions[5]);
    });

    test('a percent-encoded chapter name is matched', () async {
      positions.add(position('OEBPS/第 7 章.xhtml', 0, 6));
      addTearDown(positions.removeLast);

      await push(
        clientWith(komga),
        const RemoteProgress(
          href: '%E7%AC%AC%207%20%E7%AB%A0.xhtml',
          progression: 0.4,
          totalProgression: 0.1,
        ),
      );

      expect(saved.single['href'], 'OEBPS/第 7 章.xhtml');
    });

    test('a chapter the server copy lacks is saved by book fraction', () async {
      await push(
        clientWith(komga),
        const RemoteProgress(
          href: 'text/part0004.html',
          progression: 0.3,
          totalProgression: 0.5,
        ),
      );

      expect(saved.single, positions[2]);
    });

    test('a file name shared by two chapters is saved by book fraction', () {
      final twins = [
        position('a/ch.xhtml', 0, 1),
        position('b/ch.xhtml', 0, 2),
      ];

      expect(
        komgaPositionFor(
          twins,
          const RemoteProgress(href: 'ch.xhtml', totalProgression: 0.2),
        ),
        twins[0],
      );
    });

    test('the position list is asked for once per book', () async {
      final client = clientWith(komga);
      const progress = RemoteProgress(
        href: 'ch1.xhtml',
        progression: 0.1,
        totalProgression: 0.1,
      );

      await push(client, progress);
      await push(client, progress);

      expect(saved, hasLength(2));
      expect(positionRequests, 1);
    });

    test('a refused locator makes the next push read the list again', () async {
      var refuse = true;
      final client = clientWith(
        (request) async => request.method == 'PUT' && refuse
            ? refused('Invalid progression')
            : komga(request),
      );
      const progress = RemoteProgress(href: 'ch1.xhtml', progression: 0.1);

      await expectLater(push(client, progress), throwsA(isA<SyncException>()));
      refuse = false;
      await push(client, progress);

      expect(positionRequests, 2);
    });

    test('a refusal carries a fixed reason code, not the file name', () async {
      final client = clientWith(
        (request) async => request.method == 'GET'
            ? http.Response('', 404)
            : refused('Resource does not exist in book: OEBPS/秘密.xhtml'),
      );

      await expectLater(
        push(client, const RemoteProgress(href: 'ch1.xhtml', progression: 0.1)),
        throwsA(
          isA<SyncException>()
              .having((e) => e.statusCode, 'statusCode', 400)
              .having((e) => e.reason, 'reason', 'resource_not_in_book')
              .having((e) => '$e', 'text', isNot(contains('秘密'))),
        ),
      );
    });
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
