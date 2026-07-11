import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/ankidroid/data/services/ankidroid_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('mekuru/ankidroid_native');
  final recordedCalls = <MethodCall>[];

  void mockNativeChannel(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
          recordedCalls.add(call);
          return handler(call);
        });
  }

  Future<AnkidroidService> initializedService() async {
    final service = AnkidroidService();
    expect(await service.init(), isTrue);
    return service;
  }

  setUp(recordedCalls.clear);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('init', () {
    test('initializes when the native API is available', () async {
      mockNativeChannel((call) async {
        expect(call.method, 'isApiAvailable');
        return true;
      });

      final service = AnkidroidService();

      expect(await service.init(), isTrue);
      expect(service.isInitialized, isTrue);
    });

    test('stays uninitialized when AnkiDroid is not installed', () async {
      mockNativeChannel((call) async => false);

      final service = AnkidroidService();

      expect(await service.init(), isFalse);
      expect(service.isInitialized, isFalse);
    });

    test('stays uninitialized when the channel is unavailable', () async {
      final service = AnkidroidService();

      expect(await service.init(), isFalse);
      expect(service.isInitialized, isFalse);
    });

    test('does not re-query the channel once initialized', () async {
      mockNativeChannel((call) async => true);
      final service = await initializedService();

      await service.init();

      expect(
        recordedCalls.where((call) => call.method == 'isApiAvailable'),
        hasLength(1),
      );
    });
  });

  group('getModelList', () {
    test('returns models keyed by id', () async {
      mockNativeChannel((call) async {
        if (call.method == 'isApiAvailable') return true;
        expect(call.method, 'getModelList');
        return {1607392319495: 'Basic', 1607392319496: 'Cloze'};
      });
      final service = await initializedService();

      final models = await service.getModelList();

      expect(models, {1607392319495: 'Basic', 1607392319496: 'Cloze'});
    });

    test('returns empty map when uninitialized', () async {
      mockNativeChannel(
        (call) async => fail('must not touch the channel uninitialized'),
      );

      expect(await AnkidroidService().getModelList(), isEmpty);
    });

    test('returns empty map on platform error', () async {
      mockNativeChannel((call) async {
        if (call.method == 'isApiAvailable') return true;
        throw PlatformException(code: 'saf_io_error');
      });
      final service = await initializedService();

      expect(await service.getModelList(), isEmpty);
    });
  });

  group('getFieldList', () {
    test('passes modelId and returns field names', () async {
      mockNativeChannel((call) async {
        if (call.method == 'isApiAvailable') return true;
        expect(call.method, 'getFieldList');
        expect(call.arguments, {'modelId': 42});
        return ['Front', 'Back'];
      });
      final service = await initializedService();

      expect(await service.getFieldList(42), ['Front', 'Back']);
    });

    test('returns empty list when native side returns null', () async {
      mockNativeChannel((call) async {
        if (call.method == 'isApiAvailable') return true;
        return null;
      });
      final service = await initializedService();

      expect(await service.getFieldList(42), isEmpty);
    });
  });

  group('getDeckList', () {
    test('returns decks keyed by id', () async {
      mockNativeChannel((call) async {
        if (call.method == 'isApiAvailable') return true;
        expect(call.method, 'getDeckList');
        return {1: 'Default', 1607392319500: '日本語'};
      });
      final service = await initializedService();

      expect(await service.getDeckList(), {1: 'Default', 1607392319500: '日本語'});
    });
  });

  group('addNote', () {
    test('passes note data and returns the new note id', () async {
      mockNativeChannel((call) async {
        if (call.method == 'isApiAvailable') return true;
        expect(call.method, 'addNote');
        expect(call.arguments, {
          'modelId': 7,
          'deckId': 9,
          'fields': ['言葉', 'ことば'],
          'tags': ['mekuru'],
        });
        return 12345;
      });
      final service = await initializedService();

      final noteId = await service.addNote(
        modelId: 7,
        deckId: 9,
        fields: ['言葉', 'ことば'],
      );

      expect(noteId, 12345);
    });

    test('returns null when uninitialized', () async {
      mockNativeChannel(
        (call) async => fail('must not touch the channel uninitialized'),
      );

      final noteId = await AnkidroidService().addNote(
        modelId: 7,
        deckId: 9,
        fields: ['言葉'],
      );

      expect(noteId, isNull);
    });

    test('returns null on platform error', () async {
      mockNativeChannel((call) async {
        if (call.method == 'isApiAvailable') return true;
        throw PlatformException(code: 'saf_io_error');
      });
      final service = await initializedService();

      final noteId = await service.addNote(
        modelId: 7,
        deckId: 9,
        fields: ['言葉'],
      );

      expect(noteId, isNull);
    });
  });

  group('hasDuplicateInDeck', () {
    test('trims the field value and returns the native result', () async {
      mockNativeChannel((call) async {
        expect(call.method, 'hasDuplicateInDeck');
        expect(call.arguments, {
          'modelId': 7,
          'deckId': 9,
          'firstFieldValue': '言葉',
        });
        return true;
      });

      final result = await AnkidroidService().hasDuplicateInDeck(
        modelId: 7,
        deckId: 9,
        firstFieldValue: ' 言葉 ',
      );

      expect(result, isTrue);
    });

    test('returns false for a blank field value without a channel call',
        () async {
      mockNativeChannel((call) async => fail('must not touch the channel'));

      final result = await AnkidroidService().hasDuplicateInDeck(
        modelId: 7,
        deckId: 9,
        firstFieldValue: '   ',
      );

      expect(result, isFalse);
    });
  });

  group('dispose', () {
    test('resets the initialized state', () async {
      mockNativeChannel((call) async => true);
      final service = await initializedService();

      service.dispose();

      expect(service.isInitialized, isFalse);
    });
  });
}
