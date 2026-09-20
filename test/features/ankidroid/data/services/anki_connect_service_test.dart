import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mekuru/features/ankidroid/data/services/anki_connect_service.dart';

void main() {
  const url = 'http://192.168.1.20:8765';

  /// Requests seen by the fake AnkiConnect, decoded.
  late List<Map<String, dynamic>> requests;

  /// Builds a service whose AnkiConnect answers each action from [results];
  /// a String under `error:<action>` makes that action fail.
  AnkiConnectService serviceWith(Map<String, Object?> results) {
    requests = [];
    return AnkiConnectService(
      url,
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        requests.add(body);
        final action = body['action'] as String;
        // Bytes without a charset, as AnkiConnect sends them.
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'result': results[action],
              'error': results['error:$action'],
            }),
          ),
          200,
        );
      }),
    );
  }

  const anki = <String, Object?>{
    'version': 6,
    'modelNamesAndIds': {'Basic': 1700000000001, '日本語': 1700000000002},
    'deckNamesAndIds': {'Default': 1, 'Mining': 1700000000003},
    'modelFieldNames': ['Front', 'Back'],
    'findNotes': [1700000000004],
    'addNote': 1700000000005,
  };

  group('init', () {
    test('initializes when AnkiConnect speaks version 6', () async {
      final service = serviceWith(anki);
      expect(await service.requestPermission(), isTrue);
      expect(await service.init(), isTrue);
      expect(service.isInitialized, isTrue);
      expect(requests.single, {
        'action': 'version',
        'version': 6,
        'params': <String, dynamic>{},
      });
    });

    test('rejects an older AnkiConnect', () async {
      final service = serviceWith({'version': 5});
      expect(await service.init(), isFalse);
    });

    test('does not send a request to an invalid address', () async {
      for (final bad in ['', '192.168.1.20:8765', 'ftp://host', 'http://']) {
        expect(AnkiConnectService.isValidUrl(bad), isFalse, reason: bad);
      }
      expect(AnkiConnectService.isValidUrl(url), isTrue);
      expect(await AnkiConnectService('').init(), isFalse);
    });
  });

  test('inverts names-and-ids into id-keyed maps', () async {
    final service = serviceWith(anki);
    await service.init();
    expect(await service.getModelList(), {
      1700000000001: 'Basic',
      1700000000002: '日本語',
    });
    expect(await service.getDeckList(), {
      1: 'Default',
      1700000000003: 'Mining',
    });
  });

  test('getFieldList asks by model name; an unknown model is empty', () async {
    final service = serviceWith(anki);
    await service.init();
    expect(await service.getFieldList(1700000000002), ['Front', 'Back']);
    expect(requests.last['params'], {'modelName': '日本語'});
    expect(await service.getFieldList(42), isEmpty);
  });

  test('hasDuplicateInDeck escapes the searched value', () async {
    final service = serviceWith(anki);
    expect(
      await service.hasDuplicateInDeck(
        modelId: 1700000000001,
        deckId: 1700000000003,
        firstFieldValue: r'  say "hi" \ bye ',
      ),
      isTrue,
    );
    expect(requests.last['action'], 'findNotes');
    expect(
      (requests.last['params'] as Map)['query'],
      r'"deck:Mining" "note:Basic" "Front:say \"hi\" \\ bye"',
    );

    final before = requests.length;
    expect(
      await service.hasDuplicateInDeck(
        modelId: 1700000000001,
        deckId: 1,
        firstFieldValue: '  ',
      ),
      isFalse,
    );
    expect(requests, hasLength(before));
  });

  group('addNote', () {
    test('sends names, zipped fields and allowDuplicate', () async {
      final service = serviceWith(anki);
      await service.init();
      final noteId = await service.addNote(
        modelId: 1700000000001,
        deckId: 1700000000003,
        fields: ['食べる', 'to eat'],
        tags: ['mekuru', 'manga'],
      );
      expect(noteId, 1700000000005);
      expect(requests.last, {
        'action': 'addNote',
        'version': 6,
        'params': {
          'note': {
            'deckName': 'Mining',
            'modelName': 'Basic',
            'fields': {'Front': '食べる', 'Back': 'to eat'},
            'tags': ['mekuru', 'manga'],
            'options': {'allowDuplicate': true},
          },
        },
      });
    });

    test('throws AnkiConnect errors without the user-named part', () async {
      final service = serviceWith({
        ...anki,
        'addNote': null,
        'error:addNote': 'deck was not found: My Secret Deck',
      });
      await service.init();
      await expectLater(
        service.addNote(modelId: 1700000000001, deckId: 1, fields: ['a', 'b']),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            allOf(contains('deck was not found'), isNot(contains('Secret'))),
          ),
        ),
      );
    });

    test('returns null before init', () async {
      final service = serviceWith(anki);
      expect(
        await service.addNote(modelId: 1, deckId: 1, fields: ['a']),
        isNull,
      );
      expect(requests, isEmpty);
    });
  });

  test('network failures degrade gracefully, but addNote throws', () async {
    var down = false;
    final service = AnkiConnectService(
      url,
      client: MockClient((request) async {
        if (down) throw http.ClientException('unreachable', request.url);
        return http.Response('{"result": 6, "error": null}', 200);
      }),
    );
    await service.init();
    down = true;

    expect(await service.getModelList(), isEmpty);
    expect(await service.getDeckList(), isNull);
    expect(await service.getFieldList(1), isNull);
    expect(
      await service.hasDuplicateInDeck(
        modelId: 1,
        deckId: 1,
        firstFieldValue: 'x',
      ),
      isFalse,
    );
    await expectLater(
      service.addNote(modelId: 1, deckId: 1, fields: ['x']),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          isNot(contains('192.168')),
        ),
      ),
    );

    // A host that never answered stays uninitialized and never throws.
    final offline = AnkiConnectService(
      url,
      client: MockClient((request) async {
        throw http.ClientException('unreachable', request.url);
      }),
    );
    expect(await offline.init(), isFalse);
    expect(await offline.getDeckList(), isNull);
  });
}
