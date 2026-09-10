import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/wanikani_snapshot.dart';

/// What one kanji sync yields: rune → SRS stage, plus the subject catalogue
/// (subject id → rune) the stages were joined through, for the caller to
/// cache and hand back next time.
typedef KanjiStages = ({Map<int, int> stages, Map<int, int> subjectRunes});

/// Read-only client for the WaniKani v2 API — just enough to validate a
/// personal access token and pull the SRS stage of every kanji. Pure Dart;
/// the HTTP client is injectable for tests.
class WanikaniApiClient {
  /// Where a user creates or copies a v2 personal access token.
  static final Uri tokenPageUrl = Uri.https(
    'www.wanikani.com',
    '/settings/personal_access_tokens',
  );

  static const _baseUrl = 'https://api.wanikani.com/v2';
  static const _revision = '20170710';

  /// Kanji subjects fit in ~3 pages of 1000 and assignments in ~5 of 500;
  /// anything past this is a broken `next_url` loop, not data.
  static const maxPages = 20;

  final http.Client _http;
  final Duration _timeout;

  WanikaniApiClient({
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 20),
  }) : _http = httpClient ?? http.Client(),
       _timeout = timeout;

  /// Validates [token] (a bad one surfaces as `token_invalid`) and returns
  /// the account it belongs to.
  Future<WanikaniUser> fetchUser(String token) async {
    final data = _as<Map>((await _getJson('$_baseUrl/user', token))['data']);
    return WanikaniUser(
      username: _as<String>(data['username']),
      level: _as<int>(data['level']),
    );
  }

  /// Every kanji the account has an assignment for, as rune → SRS stage
  /// (0 unlocked … 9 burned). Assignments are always refetched (~5 small
  /// pages); the multi-megabyte subject catalogue only when an assignment
  /// names a subject missing from [subjectRunes] — i.e. on the first sync
  /// and whenever WaniKani adds kanji.
  // ponytail: assignments are a full refetch (~5 requests) per sync; switch
  // to updated_after deltas if the 60 req/min limit ever bites.
  Future<KanjiStages> fetchKanjiStages(
    String token, {
    Map<int, int> subjectRunes = const {},
  }) async {
    final stageBySubjectId = <int, int>{};
    await for (final assignment in _collection(
      '$_baseUrl/assignments?subject_types=kanji',
      token,
    )) {
      final data = _as<Map>(assignment['data']);
      stageBySubjectId[_as<int>(data['subject_id'])] = _as<int>(
        data['srs_stage'],
      );
    }

    var runeBySubjectId = subjectRunes;
    if (stageBySubjectId.keys.any((id) => !runeBySubjectId.containsKey(id))) {
      runeBySubjectId = <int, int>{};
      await for (final subject in _collection(
        '$_baseUrl/subjects?types=kanji',
        token,
      )) {
        final characters = _as<Map>(subject['data'])['characters'];
        if (characters is! String || characters.isEmpty) continue;
        runeBySubjectId[_as<int>(subject['id'])] = characters.runes.first;
      }
    }

    return (
      stages: {
        for (final entry in stageBySubjectId.entries)
          ?runeBySubjectId[entry.key]: entry.value,
      },
      subjectRunes: runeBySubjectId,
    );
  }

  /// Yields every resource of a paged collection, following `pages.next_url`.
  Stream<Map<String, dynamic>> _collection(
    String firstUrl,
    String token,
  ) async* {
    String? url = firstUrl;
    for (var page = 0; url != null; page++) {
      if (page >= maxPages) {
        throw const WanikaniException(
          WanikaniException.malformed,
          message: 'pagination did not terminate',
        );
      }
      final json = await _getJson(url, token);
      for (final item in _as<List>(json['data'])) {
        yield _as<Map>(item).cast<String, dynamic>();
      }
      final next = _as<Map>(json['pages'])['next_url'];
      url = next is String && next.isNotEmpty ? next : null;
    }
  }

  Future<Map<String, dynamic>> _getJson(String url, String token) async {
    final http.Response response;
    try {
      response = await _http
          .get(
            Uri.parse(url),
            headers: {
              'Authorization': 'Bearer $token',
              'Wanikani-Revision': _revision,
              'Accept': 'application/json',
            },
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const WanikaniException(
        WanikaniException.network,
        message: 'timed out',
      );
    } on SocketException catch (e) {
      throw WanikaniException(WanikaniException.network, message: e.message);
    } on http.ClientException catch (e) {
      throw WanikaniException(WanikaniException.network, message: e.message);
    }

    final status = response.statusCode;
    if (status == 401) {
      throw const WanikaniException(
        WanikaniException.tokenInvalid,
        statusCode: 401,
      );
    }
    if (status == 429) {
      throw const WanikaniException(
        WanikaniException.rateLimited,
        statusCode: 429,
      );
    }
    if (status < 200 || status >= 300) {
      throw WanikaniException(
        WanikaniException.http,
        statusCode: status,
        message: 'HTTP $status',
      );
    }

    try {
      // JSON is UTF-8 by spec; decoding bodyBytes sidesteps a missing
      // charset in content-type (package:http would assume latin1).
      return _as<Map>(
        jsonDecode(utf8.decode(response.bodyBytes)),
      ).cast<String, dynamic>();
    } on FormatException catch (e) {
      throw WanikaniException(WanikaniException.malformed, message: e.message);
    }
  }

  /// Narrows a decoded JSON value or reports the payload as malformed.
  static T _as<T>(Object? value) => value is T
      ? value
      : throw WanikaniException(
          WanikaniException.malformed,
          message: 'expected $T',
        );
}
