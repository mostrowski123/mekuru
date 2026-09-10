import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/wanikani_snapshot.dart';

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
    final data = _mapOf((await _getJson('$_baseUrl/user', token))['data']);
    return WanikaniUser(
      username: _stringOf(data['username']),
      level: _intOf(data['level']),
    );
  }

  /// Every kanji the account has an assignment for, as rune → SRS stage
  /// (0 unlocked … 9 burned). Two paged collections joined on subject id.
  // ponytail: full refetch (~9 requests) per sync; switch to updated_after
  // deltas if the 60 req/min limit ever bites.
  Future<Map<int, int>> fetchKanjiStages(String token) async {
    final runeBySubjectId = <int, int>{};
    await for (final subject in _collection(
      '$_baseUrl/subjects?types=kanji',
      token,
    )) {
      final characters = _mapOf(subject['data'])['characters'];
      if (characters is! String || characters.isEmpty) continue;
      runeBySubjectId[_intOf(subject['id'])] = characters.runes.first;
    }

    final stages = <int, int>{};
    await for (final assignment in _collection(
      '$_baseUrl/assignments?subject_types=kanji',
      token,
    )) {
      final data = _mapOf(assignment['data']);
      final rune = runeBySubjectId[_intOf(data['subject_id'])];
      if (rune == null) continue;
      stages[rune] = _intOf(data['srs_stage']);
    }
    return stages;
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
      for (final item in _listOf(json['data'])) {
        yield _mapOf(item);
      }
      final next = _mapOf(json['pages'])['next_url'];
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
      return _mapOf(jsonDecode(utf8.decode(response.bodyBytes)));
    } on FormatException catch (e) {
      throw WanikaniException(WanikaniException.malformed, message: e.message);
    }
  }

  static Map<String, dynamic> _mapOf(Object? value) => value is Map
      ? value.cast<String, dynamic>()
      : throw const WanikaniException(
          WanikaniException.malformed,
          message: 'expected an object',
        );

  static List<Object?> _listOf(Object? value) => value is List
      ? value
      : throw const WanikaniException(
          WanikaniException.malformed,
          message: 'expected a list',
        );

  static int _intOf(Object? value) => value is int
      ? value
      : throw const WanikaniException(
          WanikaniException.malformed,
          message: 'expected an integer',
        );

  static String _stringOf(Object? value) => value is String
      ? value
      : throw const WanikaniException(
          WanikaniException.malformed,
          message: 'expected a string',
        );
}
