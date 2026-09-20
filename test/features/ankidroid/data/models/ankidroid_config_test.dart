import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/ankidroid/data/models/ankidroid_config.dart';

void main() {
  test('the AnkiMobile values survive a JSON round trip', () {
    const config = AnkidroidConfig(
      modelId: -1,
      modelName: '日本語',
      deckId: -1,
      deckName: 'Mining',
      fieldMapping: {'Front': 'expression'},
      ankiFieldNames: ['Front', 'Back'],
      useAnkiMobile: false,
      ankiMobileNoteType: '日本語',
      ankiMobileDeck: 'Mining',
      ankiMobileFields: ['Front', 'Back'],
      parkedSelection: {'modelId': 5, 'modelName': 'Basic'},
    );

    final decoded = AnkidroidConfig.decode(config.encode())!;

    expect(decoded.toJson(), config.toJson());
    expect(decoded.useAnkiMobile, isFalse);
    expect(decoded.ankiMobileFields, ['Front', 'Back']);
  });

  test('JSON from before the AnkiMobile fields defaults to AnkiMobile', () {
    final decoded = AnkidroidConfig.decode(
      jsonEncode({
        'modelId': 5,
        'modelName': 'Basic',
        'deckId': 1,
        'deckName': 'Default',
        'fieldMapping': {'Front': 'expression'},
        'tags': ['mekuru'],
      }),
    )!;

    expect(decoded.modelId, 5);
    expect(decoded.useAnkiMobile, isTrue);
    expect(decoded.ankiMobileNoteType, '');
    expect(decoded.ankiMobileDeck, '');
    expect(decoded.ankiMobileFields, isEmpty);
    expect(decoded.parkedSelection, isEmpty);
  });

  test('old JSON with an AnkiConnect address stays on AnkiConnect', () {
    final decoded = AnkidroidConfig.decode(
      jsonEncode({'ankiConnectUrl': 'http://192.168.1.20:8765'}),
    )!;

    expect(decoded.useAnkiMobile, isFalse);
  });

  test('switching backends parks the selection and brings it back', () {
    const ankiConnect = AnkidroidConfig(
      modelId: 5,
      modelName: 'Basic',
      deckId: 1,
      deckName: 'Default',
      fieldMapping: {'Front': 'expression'},
      ankiFieldNames: ['Front', 'Back'],
      useAnkiMobile: false,
      ankiMobileNoteType: 'Mobile',
    );

    final ankiMobile = ankiConnect.withUseAnkiMobile(true);
    expect(ankiMobile.useAnkiMobile, isTrue);
    expect(ankiMobile.isConfigured, isFalse);
    expect(ankiMobile.fieldMapping, isEmpty);
    expect(ankiMobile.ankiMobileNoteType, 'Mobile');

    // Through storage and back, as a real switch would go.
    final back = AnkidroidConfig.decode(
      ankiMobile.encode(),
    )!.withUseAnkiMobile(false);
    expect(back.modelId, 5);
    expect(back.modelName, 'Basic');
    expect(back.deckId, 1);
    expect(back.deckName, 'Default');
    expect(back.fieldMapping, {'Front': 'expression'});
    expect(back.ankiFieldNames, ['Front', 'Back']);
  });
}
