import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/ankidroid/data/services/anki_mobile_service.dart';

void main() {
  group('buildAddNoteUrl', () {
    final url = AnkiMobileService.buildAddNoteUrl(
      noteType: 'Japanese Basic',
      deck: '日本語::Mining',
      fieldNames: ['表面', 'Back', 'Unused'],
      fields: ['食べる', 'to eat & drink', ''],
      tags: ['mekuru', 'book'],
    );

    test('addresses the addnote action', () {
      expect(url.scheme, 'anki');
      expect(url.host, 'x-callback-url');
      expect(url.path, '/addnote');
    });

    test('percent-encodes Japanese text, spaces and separators', () {
      final raw = url.toString();
      expect(raw, contains('type=Japanese%20Basic'));
      expect(raw, contains('deck=%E6%97%A5%E6%9C%AC%E8%AA%9E%3A%3AMining'));
      expect(
        raw,
        contains('fld%E8%A1%A8%E9%9D%A2=%E9%A3%9F%E3%81%B9%E3%82%8B'),
      );
      expect(raw, contains('fldBack=to%20eat%20%26%20drink'));
      // '+' would reach AnkiMobile as a literal plus.
      expect(raw, isNot(contains('+')));
    });

    test('carries fields, space-joined tags and the way back', () {
      expect(url.queryParameters, {
        'type': 'Japanese Basic',
        'deck': '日本語::Mining',
        'fld表面': '食べる',
        'fldBack': 'to eat & drink',
        'tags': 'mekuru book',
        'x-success': 'mekuru://anki',
      });
    });

    test('leaves duplicate handling to AnkiMobile', () {
      expect(url.queryParameters.containsKey('dupes'), isFalse);
    });
  });

  group('service contract', () {
    late List<Uri> launched;

    AnkiMobileService build({
      bool installed = true,
      bool launches = true,
      String noteType = 'Basic',
    }) {
      launched = [];
      return AnkiMobileService(
        noteType: noteType,
        deck: 'Mining',
        fieldNames: const ['Front', 'Back'],
        canLaunch: (_) async => installed,
        launch: (url) async {
          launched.add(url);
          return launches;
        },
      );
    }

    Future<int?> add(AnkiMobileService service) => service.addNote(
      modelId: AnkiMobileService.syntheticId,
      deckId: AnkiMobileService.syntheticId,
      fields: ['食べる', 'to eat'],
    );

    test('without AnkiMobile init fails and addNote throws', () async {
      final service = build(installed: false);

      expect(await service.init(), isFalse);
      expect(await service.getDeckList(), isNull);
      await expectLater(add(service), throwsException);
      expect(launched, isEmpty);
    });

    test('without the configured names init fails', () async {
      expect(await build(noteType: '').init(), isFalse);
    });

    test('presents one synthetic note type and deck', () async {
      final service = build();

      expect(await service.init(), isTrue);
      expect(await service.getModelList(), {
        AnkiMobileService.syntheticId: 'Basic',
      });
      expect(await service.getDeckList(), {
        AnkiMobileService.syntheticId: 'Mining',
      });
      expect(await service.getFieldList(AnkiMobileService.syntheticId), [
        'Front',
        'Back',
      ]);
      // An id from another backend reads as a note type that is gone.
      expect(await service.getFieldList(1700000000000), isEmpty);
      expect(
        await service.hasDuplicateInDeck(
          modelId: AnkiMobileService.syntheticId,
          deckId: AnkiMobileService.syntheticId,
          firstFieldValue: '食べる',
        ),
        isFalse,
      );
    });

    test('addNote launches once and returns an id', () async {
      final service = build();
      await service.init();

      expect(await add(service), isNotNull);
      expect(launched, hasLength(1));
      expect(launched.single.queryParameters['fldFront'], '食べる');
      expect(launched.single.queryParameters['tags'], 'mekuru');
    });

    test('a failed launch throws without the note text', () async {
      final service = build(launches: false);
      await service.init();

      await expectLater(
        add(service),
        throwsA(
          isA<Exception>().having(
            (e) => '$e',
            'message',
            isNot(contains('食べる')),
          ),
        ),
      );
    });
  });
}
