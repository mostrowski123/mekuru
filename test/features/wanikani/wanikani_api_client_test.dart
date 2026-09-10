import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mekuru/features/wanikani/data/models/wanikani_snapshot.dart';
import 'package:mekuru/features/wanikani/data/services/wanikani_api_client.dart';

const _base = 'https://api.wanikani.com/v2';

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: const {
    // Deliberately no charset: the client must decode bodyBytes as UTF-8.
    'content-type': 'application/json',
  },
);

Map<String, Object?> _page(List<Object?> data, {String? next}) => {
  'object': 'collection',
  'pages': {'per_page': 500, 'next_url': next, 'previous_url': null},
  'total_count': data.length,
  'data': data,
};

Map<String, Object?> _subject(int id, String? characters) => {
  'id': id,
  'object': 'kanji',
  'data': {'characters': characters, 'level': 1, 'slug': characters ?? ''},
};

Map<String, Object?> _assignment(int subjectId, int stage) => {
  'id': subjectId * 10,
  'object': 'assignment',
  'data': {
    'subject_id': subjectId,
    'subject_type': 'kanji',
    'srs_stage': stage,
  },
};

WanikaniApiClient _client(
  Future<http.Response> Function(http.Request request) handler,
) => WanikaniApiClient(httpClient: MockClient(handler));

Matcher _throwsCode(String code, {int? status}) => throwsA(
  isA<WanikaniException>()
      .having((e) => e.code, 'code', code)
      .having((e) => e.statusCode, 'statusCode', status ?? anything),
);

void main() {
  group('WanikaniApiClient.fetchUser', () {
    test('sends the bearer token and revision header', () async {
      late http.Request seen;
      final client = _client((request) async {
        seen = request;
        return _json({
          'object': 'user',
          'data': {'username': 'crabigator', 'level': 23},
        });
      });

      final user = await client.fetchUser('tok-1');

      expect(seen.method, 'GET');
      expect(seen.url.toString(), '$_base/user');
      expect(seen.headers['Authorization'], 'Bearer tok-1');
      expect(seen.headers['Wanikani-Revision'], '20170710');
      expect(seen.headers['Accept'], 'application/json');
      expect(user.username, 'crabigator');
      expect(user.level, 23);
    });

    test('decodes non-ASCII usernames as UTF-8 without a charset', () async {
      final client = _client(
        (_) async => _json({
          'data': {'username': 'かに', 'level': 1},
        }),
      );
      expect((await client.fetchUser('t')).username, 'かに');
    });

    test('maps 401 to token_invalid', () async {
      final client = _client(
        (_) async => _json({'error': 'Unauthorized', 'code': 401}, 401),
      );
      await expectLater(
        () => client.fetchUser('bad'),
        _throwsCode(WanikaniException.tokenInvalid, status: 401),
      );
    });

    test('maps 429 to rate_limited', () async {
      final client = _client((_) async => _json({'code': 429}, 429));
      await expectLater(
        () => client.fetchUser('t'),
        _throwsCode(WanikaniException.rateLimited, status: 429),
      );
    });

    test('maps other non-2xx to http with the status', () async {
      final client = _client((_) async => http.Response('boom', 503));
      await expectLater(
        () => client.fetchUser('t'),
        _throwsCode(WanikaniException.http, status: 503),
      );
    });

    test('maps unreachable hosts to network', () async {
      final client = _client((_) async => throw const SocketException('down'));
      await expectLater(
        () => client.fetchUser('t'),
        _throwsCode(WanikaniException.network),
      );
    });

    test('maps client exceptions to network', () async {
      final client = _client(
        (_) async => throw http.ClientException('connection closed'),
      );
      await expectLater(
        () => client.fetchUser('t'),
        _throwsCode(WanikaniException.network),
      );
    });

    test('maps a timeout to network', () async {
      final client = WanikaniApiClient(
        httpClient: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return _json({'data': {}});
        }),
        timeout: const Duration(milliseconds: 1),
      );
      await expectLater(
        () => client.fetchUser('t'),
        _throwsCode(WanikaniException.network),
      );
    });

    test('maps invalid JSON and wrong shapes to malformed', () async {
      await expectLater(
        () => _client((_) async => http.Response('<html>', 200)).fetchUser('t'),
        _throwsCode(WanikaniException.malformed),
      );
      await expectLater(
        () => _client((_) async => _json([1, 2])).fetchUser('t'),
        _throwsCode(WanikaniException.malformed),
      );
      await expectLater(
        () => _client(
          (_) async => _json({
            'data': {'username': 'x', 'level': 'twelve'},
          }),
        ).fetchUser('t'),
        _throwsCode(WanikaniException.malformed),
      );
    });
  });

  group('WanikaniApiClient.fetchKanjiStages', () {
    test('joins paged subjects and assignments into rune → stage', () async {
      final calls = <String>[];
      final client = _client((request) async {
        calls.add(request.url.toString());
        expect(request.headers['Authorization'], 'Bearer tok');
        return switch (request.url.toString()) {
          '$_base/subjects?types=kanji' => _json(
            _page([
              _subject(1, '日'),
              _subject(2, '本'),
            ], next: '$_base/subjects?types=kanji&page_after_id=2'),
          ),
          '$_base/subjects?types=kanji&page_after_id=2' => _json(
            _page([_subject(3, '語'), _subject(4, null), _subject(5, '')]),
          ),
          '$_base/assignments?subject_types=kanji' => _json(
            _page([
              _assignment(1, 9),
              _assignment(2, 5),
            ], next: '$_base/assignments?subject_types=kanji&page_after_id=20'),
          ),
          '$_base/assignments?subject_types=kanji&page_after_id=20' => _json(
            _page([
              _assignment(3, 0),
              // Assignment for a subject that is not a kanji we saw.
              _assignment(99, 9),
            ]),
          ),
          _ => http.Response('unexpected', 404),
        };
      });

      final stages = await client.fetchKanjiStages('tok');

      expect(stages, {
        '日'.runes.first: 9,
        '本'.runes.first: 5,
        '語'.runes.first: 0,
      });
      expect(calls, hasLength(4));
      // Subjects are fetched before assignments so the join has its keys.
      expect(calls.first, startsWith('$_base/subjects'));
      expect(calls.last, startsWith('$_base/assignments'));
    });

    test('returns an empty map for an account with no assignments', () async {
      final client = _client((request) async {
        return request.url.path.endsWith('/subjects')
            ? _json(_page([_subject(1, '日')]))
            : _json(_page(const []));
      });
      expect(await client.fetchKanjiStages('tok'), isEmpty);
    });

    test('treats an empty next_url as the last page', () async {
      var calls = 0;
      final client = _client((request) async {
        calls++;
        return _json({
          'pages': {'next_url': ''},
          'data': const [],
        });
      });
      await client.fetchKanjiStages('tok');
      expect(calls, 2);
    });

    test('stops a never-ending next_url loop as malformed', () async {
      var calls = 0;
      final client = _client((request) async {
        calls++;
        return _json(_page(const [], next: request.url.toString()));
      });
      await expectLater(
        () => client.fetchKanjiStages('tok'),
        _throwsCode(WanikaniException.malformed),
      );
      expect(calls, WanikaniApiClient.maxPages);
    });

    test('propagates a token rejection from the subjects page', () async {
      final client = _client((_) async => http.Response('', 401));
      await expectLater(
        () => client.fetchKanjiStages('tok'),
        _throwsCode(WanikaniException.tokenInvalid, status: 401),
      );
    });

    test('rejects assignments missing srs_stage as malformed', () async {
      final client = _client((request) async {
        return request.url.path.endsWith('/subjects')
            ? _json(_page([_subject(1, '日')]))
            : _json(
                _page([
                  {
                    'id': 10,
                    'data': {'subject_id': 1},
                  },
                ]),
              );
      });
      await expectLater(
        () => client.fetchKanjiStages('tok'),
        _throwsCode(WanikaniException.malformed),
      );
    });
  });

  test('tokenPageUrl points at the personal access tokens page', () {
    expect(
      WanikaniApiClient.tokenPageUrl.toString(),
      'https://www.wanikani.com/settings/personal_access_tokens',
    );
  });
}
