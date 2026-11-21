import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Answers one request to a [LoopbackHttp] server.
typedef LoopbackHandler = Future<void> Function(HttpRequest request);

/// A server on 127.0.0.1 that every [HttpClient] made after [start] connects
/// to, whatever host its URL names, so a download whose https URL is a
/// constant can be served by the test. The routed connection skips TLS: the
/// server speaks plain HTTP.
///
/// Call it after `TestWidgetsFlutterBinding.ensureInitialized()`, whose own
/// override answers every request with 400.
class LoopbackHttp {
  LoopbackHttp._(this._server);

  final HttpServer _server;

  /// `host/path` of every request since [reset], in order.
  final requests = <String>[];

  /// The Range header of every request since [reset], null when it had none.
  final ranges = <String?>[];

  /// Answers each request; [notFound] after [reset].
  LoopbackHandler handler = notFound;

  static Future<LoopbackHttp> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final loopback = LoopbackHttp._(server);
    server.listen((request) async {
      loopback.requests.add('${request.headers.host}${request.uri.path}');
      loopback.ranges.add(request.headers.value(HttpHeaders.rangeHeader));
      try {
        await loopback.handler(request);
      } on Object {
        // The client went away mid-answer, which some tests make it do.
      }
    });
    HttpOverrides.global = _Routed(server.port);
    return loopback;
  }

  void reset() {
    requests.clear();
    ranges.clear();
    handler = notFound;
  }

  Future<void> close() async {
    HttpOverrides.global = null;
    await _server.close(force: true);
  }
}

class _Routed extends HttpOverrides {
  _Routed(this.port);

  final int port;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..findProxy = ((_) => 'DIRECT')
        ..connectionFactory = (_, _, _) =>
            Socket.startConnect(InternetAddress.loopbackIPv4, port);
}

Future<void> notFound(HttpRequest request) async {
  request.response.statusCode = HttpStatus.notFound;
  await request.response.close();
}

/// Answers with [body] whole.
LoopbackHandler serve(List<int> body) => (request) async {
  request.response.contentLength = body.length;
  request.response.add(body);
  await request.response.close();
};

/// Answers with half of [body], waits [pause], then sends the rest.
LoopbackHandler serveSlowly(List<int> body, Duration pause) => (request) async {
  request.response.contentLength = body.length;
  request.response.add(body.sublist(0, body.length ~/ 2));
  await request.response.flush();
  await Future<void>.delayed(pause);
  request.response.add(body.sublist(body.length ~/ 2));
  await request.response.close();
};

/// Promises [length] bytes, sends [sent], then drops the connection.
LoopbackHandler cutOff(List<int> sent, {required int length}) =>
    (request) async {
      final socket = await _startRaw(request, length, sent);
      socket.destroy();
    };

/// Promises [length] bytes, sends [sent], then sends nothing more until the
/// client closes the connection.
LoopbackHandler stall(List<int> sent, {required int length}) =>
    (request) async {
      final socket = await _startRaw(request, length, sent);
      try {
        await socket.drain<void>();
      } finally {
        socket.destroy();
      }
    };

Future<Socket> _startRaw(
  HttpRequest request,
  int length,
  List<int> sent,
) async {
  final socket = await request.response.detachSocket(writeHeaders: false);
  socket.add(
    ascii.encode('HTTP/1.1 200 OK\r\ncontent-length: $length\r\n\r\n'),
  );
  socket.add(sent);
  await socket.flush();
  return socket;
}
