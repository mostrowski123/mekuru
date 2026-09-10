import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mekuru/core/services/http_transport.dart';

import 'server_client.dart';

/// Transport shared by the HTTP-backed clients: base-URL normalization,
/// request timeout, transport-error → [SyncException] mapping, and JSON
/// decoding. Subclasses put authentication in [send].
abstract class HttpServerClient implements ServerClient {
  final String baseUrl;
  final http.Client httpClient;
  final Duration requestTimeout;

  /// Server name used in error messages.
  final String serverName;

  HttpServerClient({
    required String baseUrl,
    required this.serverName,
    http.Client? httpClient,
    this.requestTimeout = const Duration(seconds: 15),
  }) : baseUrl = baseUrl.endsWith('/')
           ? baseUrl.substring(0, baseUrl.length - 1)
           : baseUrl,
       httpClient = httpClient ?? http.Client();

  /// Send a request and return the response whatever its status; transport
  /// failures (timeout, unreachable host) become [SyncException]s.
  Future<http.Response> sendRaw(
    String method,
    String path, {
    Map<String, String>? headers,
    Map<String, dynamic>? body,
  }) async {
    final request = http.Request(method, Uri.parse('$baseUrl$path'))
      ..headers['Accept'] = 'application/json';
    if (headers != null) request.headers.addAll(headers);
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    try {
      return await sendWithTimeout(
        httpClient,
        request,
        timeout: requestTimeout,
      );
    } on NetworkException catch (e) {
      throw SyncException(
        0,
        e.timedOut
            ? '$serverName server timed out'
            : 'Cannot reach $serverName server: ${e.message}',
      );
    }
  }

  /// Authenticated request that must succeed (2xx), else [SyncException].
  Future<http.Response> send(
    String method,
    String path, {
    Map<String, dynamic>? body,
  });

  /// [response] when it is 2xx; throws [SyncException] otherwise.
  http.Response ensureSuccess(
    http.Response response,
    String method,
    String path,
  ) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SyncException(
        response.statusCode,
        '$serverName request failed: $method $path',
      );
    }
    return response;
  }

  Future<dynamic> getJson(String path) async =>
      decodeJsonBody(await send('GET', path));

  @override
  void dispose() => httpClient.close();
}
