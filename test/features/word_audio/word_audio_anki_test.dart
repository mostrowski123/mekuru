import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/ankidroid/data/models/anki_note_data.dart';
import 'package:mekuru/features/ankidroid/data/models/ankidroid_config.dart';
import 'package:mekuru/features/ankidroid/data/services/anki_connect_service.dart';
import 'package:mekuru/features/ankidroid/data/services/anki_field_mapper.dart';
import 'package:mekuru/features/ankidroid/data/services/anki_mobile_service.dart';
import 'package:mekuru/features/ankidroid/data/services/ankidroid_service.dart';
import 'package:mekuru/features/ankidroid/presentation/providers/ankidroid_providers.dart';
import 'package:mekuru/features/ankidroid/presentation/screens/anki_card_creation_screen.dart';
import 'package:mekuru/features/word_audio/data/services/word_audio.dart';
import 'package:mekuru/features/word_audio/presentation/providers/word_audio_providers.dart';
import 'package:mekuru/main.dart' show databaseProvider;
import 'package:path/path.dart' as p;

import '../../shared/test_database.dart';
import '../../test_app.dart';
import '../ankidroid/ankidroid_test_doubles.dart';

const _clip = 'f84aff2662b3f2f2';
const _placeholder = '[sound:mekuru_$_clip.mp3]';

/// A clip already on this device, so no route needs the network or a plugin.
class _LocalClipAudio extends WordAudio {
  _LocalClipAudio(this.path) : super(base: 'https://audio.test/v1');
  final String path;

  @override
  Future<WordAudioClip> clipFile(String id) async =>
      (path: path, source: 'cache');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the Word Audio source', () {
    const note = AnkiNoteData(
      expression: '学校',
      reading: 'がっこう',
      glossaries: '["school"]',
      dictionaryName: 'JMdict',
      wordAudioClipId: _clip,
    );

    test('writes a placeholder until the card is sent', () {
      expect(AppDataSource.wordAudio.valueFor(note), _placeholder);
    });

    test('is empty for a word without a clip', () {
      const none = AnkiNoteData(
        expression: '学校',
        reading: 'がっこう',
        glossaries: '["school"]',
        dictionaryName: 'JMdict',
      );
      expect(AppDataSource.wordAudio.valueFor(none), '');
    });

    test('reads back from its stored key', () {
      expect(AppDataSource.fromKey('word_audio'), AppDataSource.wordAudio);
    });
  });

  group('the three routes', () {
    late Directory dir;
    late WordAudio audio;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('word_audio_anki');
      final file = File(p.join(dir.path, '$_clip.mp3'))
        ..writeAsBytesSync(const [1, 2, 3]);
      audio = _LocalClipAudio(file.path);
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('AnkiDroid is handed the file and answers with its text', () async {
      const channel = MethodChannel('mekuru/ankidroid_native');
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'isApiAvailable'
            ? true
            : '[sound:mekuru_${_clip}_123.mp3]';
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final service = AnkidroidService();
      await service.init();

      expect(
        await service.audioFieldValue(audio, _clip),
        '[sound:mekuru_${_clip}_123.mp3]',
      );
      expect(calls.last.method, 'addMedia');
      expect(calls.last.arguments, {
        'path': p.join(dir.path, '$_clip.mp3'),
        'name': 'mekuru_$_clip',
      });
    });

    test('AnkiDroid not available: no media and no call', () async {
      expect(await AnkidroidService().audioFieldValue(audio, _clip), isNull);
    });

    test('AnkiMobile gets the hosted link', () async {
      final service = AnkiMobileService(
        noteType: 'Basic',
        deck: 'Default',
        fieldNames: const ['Front'],
      );
      expect(
        await service.audioFieldValue(audio, _clip),
        'https://audio.test/v1/clips/f8/$_clip.mp3',
      );
    });

    test('AnkiConnect stores the bytes under the name it answers', () async {
      late Map<String, dynamic> sent;
      final service = AnkiConnectService(
        'http://192.168.1.20:8765',
        client: MockClient((request) async {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"result":"_renamed.mp3","error":null}', 200);
        }),
      );

      expect(
        await service.audioFieldValue(audio, _clip),
        '[sound:_renamed.mp3]',
      );
      expect(sent['action'], 'storeMediaFile');
      expect(sent['params'], {
        'filename': 'mekuru_$_clip.mp3',
        'data': base64Encode(const [1, 2, 3]),
      });
    });

    test('an AnkiConnect error throws, so the card can go without', () async {
      final service = AnkiConnectService(
        'http://192.168.1.20:8765',
        client: MockClient(
          (_) async => http.Response('{"result":null,"error":"nope"}', 200),
        ),
      );
      await expectLater(
        service.audioFieldValue(audio, _clip),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('the card screen', () {
    late AppDatabase db;
    late FakeAnkidroidService service;
    Object? popped;

    setUp(() {
      db = createTestDatabase();
      service = FakeAnkidroidService();
      popped = null;
    });

    tearDown(() async => db.close());

    Future<void> pumpScreen(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ankidroidServiceProvider.overrideWithValue(service),
            ankidroidConfigProvider.overrideWith(
              () => TestAnkidroidConfigNotifier(
                const AnkidroidConfig(
                  modelId: 5,
                  modelName: 'Basic',
                  deckId: 1,
                  deckName: 'Default',
                  fieldMapping: {'Front': 'expression', 'Back': 'word_audio'},
                ),
              ),
            ),
            databaseProvider.overrideWithValue(db),
            wordAudioProvider.overrideWithValue(_LocalClipAudio('unused')),
          ],
          child: buildLocalizedTestApp(
            home: Builder(
              builder: (context) => FilledButton(
                onPressed: () async =>
                    popped = await Navigator.of(context).push<AnkiCardResult>(
                      MaterialPageRoute(
                        builder: (_) => const AnkiCardCreationScreen(
                          noteData: AnkiNoteData(
                            expression: '学校',
                            reading: 'がっこう',
                            glossaries: '["school"]',
                            dictionaryName: 'JMdict',
                            wordAudioClipId: _clip,
                          ),
                          entryGlossaries: '["school"]',
                        ),
                      ),
                    ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('the field shows the placeholder; sending swaps it', (
      tester,
    ) async {
      service.audioValue = '[sound:stored.mp3]';
      await pumpScreen(tester);

      expect(find.text(_placeholder), findsOneWidget);
      expect(service.audioRequests, isEmpty);

      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(service.audioRequests, [_clip]);
      expect(service.sentFields, ['学校', '[sound:stored.mp3]']);
      expect(popped, AnkiCardResult.sent);
    });

    testWidgets('failed audio still sends the card, with an empty field', (
      tester,
    ) async {
      service.audioError = const SocketException('offline');
      await pumpScreen(tester);

      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(service.sentFields, ['学校', '']);
      expect(popped, AnkiCardResult.sentWithoutAudio);
    });

    testWidgets('the user clearing the field adds no media', (tester) async {
      await pumpScreen(tester);

      await tester.enterText(find.text(_placeholder), '');
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(service.audioRequests, isEmpty);
      expect(service.sentFields, ['学校', '']);
      expect(popped, AnkiCardResult.sent);
    });
  });
}
