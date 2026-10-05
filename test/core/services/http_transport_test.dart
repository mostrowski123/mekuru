import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mekuru/core/services/http_transport.dart';

void main() {
  // A Request can only be sent once, so each call builds its own.
  Future<http.Response> send(
    Future<http.Response> Function(http.Request) handler, {
    Duration timeout = const Duration(seconds: 1),
  }) => sendWithTimeout(
    MockClient(handler),
    http.Request('GET', Uri.parse('https://example.test/x')),
    timeout: timeout,
  );

  group('sendWithTimeout', () {
    test('returns the response whatever its status', () async {
      final response = await send((_) async => http.Response('nope', 503));
      expect(response.statusCode, 503);
      expect(response.body, 'nope');
    });

    test('a timeout becomes NetworkException(timedOut)', () async {
      await expectLater(
        () => send((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return http.Response('', 200);
        }, timeout: const Duration(milliseconds: 1)),
        throwsA(
          isA<NetworkException>().having((e) => e.timedOut, 'timedOut', true),
        ),
      );
    });

    // A body that sends [chunks] chunks [every] apart, then stays open
    // without sending more when [stall], instead of ending.
    Future<http.Response> sendBody({
      required int chunks,
      required Duration every,
      bool stall = false,
    }) {
      final body = StreamController<List<int>>();
      () async {
        for (var i = 0; i < chunks; i++) {
          await Future<void>.delayed(every);
          body.add([i]);
        }
        if (!stall) await body.close();
      }();
      return sendWithTimeout(
        MockClient.streaming(
          (request, _) async => http.StreamedResponse(body.stream, 200),
        ),
        http.Request('GET', Uri.parse('https://example.test/x')),
        timeout: const Duration(milliseconds: 100),
      );
    }

    test('a body that stalls becomes NetworkException(timedOut)', () async {
      await expectLater(
        () => sendBody(chunks: 1, every: Duration.zero, stall: true),
        throwsA(
          isA<NetworkException>().having((e) => e.timedOut, 'timedOut', true),
        ),
      );
    });

    test('a slow body that keeps coming still arrives in full', () async {
      // 400 ms in all, but never 100 ms without a chunk.
      final response = await sendBody(
        chunks: 8,
        every: const Duration(milliseconds: 50),
      );
      expect(response.bodyBytes, [0, 1, 2, 3, 4, 5, 6, 7]);
    });

    test('socket and client failures keep their message', () async {
      await expectLater(
        () => send((_) async => throw const SocketException('host down')),
        throwsA(
          isA<NetworkException>()
              .having((e) => e.message, 'message', 'host down')
              .having((e) => e.timedOut, 'timedOut', false),
        ),
      );
      await expectLater(
        () => send((_) async => throw http.ClientException('closed')),
        throwsA(
          isA<NetworkException>().having((e) => e.message, 'message', 'closed'),
        ),
      );
    });

    test('a host dart:io refuses becomes NetworkException', () async {
      await expectLater(
        () => send(
          (_) async => throw const FormatException(
            '%3C192.168.1.5%3E is not a valid link-local address but '
            'contains %.',
          ),
        ),
        throwsA(isA<NetworkException>()),
      );
    });

    test('other errors pass through untouched', () async {
      await expectLater(
        () => send((_) async => throw StateError('bug')),
        throwsStateError,
      );
    });
  });

  test('decodeJsonBody reads UTF-8 without a charset header', () {
    final response = http.Response.bytes(
      utf8.encode('{"name":"かに"}'),
      200,
      headers: const {'content-type': 'application/json'},
    );
    expect(decodeJsonBody(response), {'name': 'かに'});
  });
}
