/// The pieces every HTTP client here needs and none should re-implement:
/// sending with a timeout while folding package:http's pre-response failures
/// into one exception, and decoding a JSON body as the UTF-8 it is.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// The request never produced an HTTP response: DNS or socket failure, a host
/// dart:io refuses, a connection closed mid-flight, or no answer within the
/// timeout. Carries no
/// status code — callers map it to their own "network unavailable" case.
class NetworkException implements Exception {
  final String message;
  final bool timedOut;

  const NetworkException(this.message, {this.timedOut = false});

  @override
  String toString() => 'NetworkException: $message';
}

/// Sends [request] on [client], waiting at most [timeout] for the response
/// headers, then at most [timeout] between chunks of the body: a long body
/// still arrives, a stalled one fails. Every way package:http can fail
/// before a full response exists becomes a [NetworkException]; status codes
/// are the caller's business.
Future<http.Response> sendWithTimeout(
  http.Client client,
  http.BaseRequest request, {
  required Duration timeout,
}) async {
  try {
    final streamed = await client.send(request).timeout(timeout);
    return http.Response.bytes(
      await _readBody(streamed.stream, timeout),
      streamed.statusCode,
      request: streamed.request,
      headers: streamed.headers,
      isRedirect: streamed.isRedirect,
      persistentConnection: streamed.persistentConnection,
      reasonPhrase: streamed.reasonPhrase,
    );
  } on TimeoutException {
    throw const NetworkException('timed out', timedOut: true);
  } on SocketException catch (e) {
    throw NetworkException(e.message);
  } on http.ClientException catch (e) {
    throw NetworkException(e.message);
  } on FormatException catch (e) {
    // dart:io refuses a host it can't connect to (e.g. `%3C…%3E` from a URL
    // typed with `<` `>`) before opening a socket.
    throw NetworkException(e.message);
  }
}

/// All of [body], failing with a [TimeoutException] when no chunk arrives
/// for [idle]. By hand, not with Stream.timeout: under flutter_test's fake
/// clock that holds a response back until the real event loop runs, which
/// widget tests that only pump never let happen.
Future<Uint8List> _readBody(Stream<List<int>> body, Duration idle) {
  final completer = Completer<Uint8List>();
  final bytes = BytesBuilder(copy: false);
  Timer? timer;
  late final StreamSubscription<List<int>> subscription;
  void waitForMore() {
    timer?.cancel();
    timer = Timer(idle, () {
      subscription.cancel();
      completer.completeError(TimeoutException('No data', idle));
    });
  }

  subscription = body.listen(
    (chunk) {
      bytes.add(chunk);
      waitForMore();
    },
    onError: (Object error, StackTrace stack) {
      timer?.cancel();
      completer.completeError(error, stack);
    },
    onDone: () {
      timer?.cancel();
      completer.complete(bytes.takeBytes());
    },
    cancelOnError: true,
  );
  waitForMore();
  return completer.future;
}

/// JSON is UTF-8 by spec; decoding [http.Response.bodyBytes] directly
/// sidesteps servers that omit charset from content-type (package:http
/// would then assume latin1 and mangle non-ASCII text).
Object? decodeJsonBody(http.Response response) =>
    jsonDecode(utf8.decode(response.bodyBytes));
