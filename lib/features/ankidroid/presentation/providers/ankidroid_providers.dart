import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/ankidroid/data/models/ankidroid_config.dart';
import 'package:mekuru/features/ankidroid/data/services/anki_connect_service.dart';
import 'package:mekuru/features/ankidroid/data/services/anki_mobile_service.dart';
import 'package:mekuru/features/ankidroid/data/services/ankidroid_service.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';

/// Whether this platform exports to Anki through the iOS backends (AnkiMobile
/// on the device, or the AnkiConnect desktop add-on) instead of AnkiDroid.
bool get usesIosAnki => defaultTargetPlatform == TargetPlatform.iOS;

/// User-visible name of the Anki app this platform exports to.
String get ankiAppName => usesIosAnki ? 'Anki' : 'AnkiDroid';

/// Provider for the Anki service singleton: AnkiDroid on Android; on iOS the
/// configured backend, rebuilt when the values it is built from change.
final ankidroidServiceProvider = Provider<AnkidroidService>((ref) {
  final AnkidroidService service;
  if (!usesIosAnki) {
    service = AnkidroidService();
  } else if (ref.watch(
    ankidroidConfigProvider.select((c) => c.useAnkiMobile),
  )) {
    final (noteType, deck, fieldNames) = ref.watch(
      ankidroidConfigProvider.select(
        (c) => (c.ankiMobileNoteType, c.ankiMobileDeck, c.ankiMobileFields),
      ),
    );
    service = AnkiMobileService(
      noteType: noteType,
      deck: deck,
      fieldNames: fieldNames,
    );
  } else {
    service = AnkiConnectService(
      ref.watch(ankidroidConfigProvider.select((c) => c.ankiConnectUrl)),
    );
  }
  ref.onDispose(() => service.dispose());
  return service;
});

/// Whether the current platform supports Anki card export.
final ankidroidAvailableProvider = Provider<bool>((ref) {
  return defaultTargetPlatform == TargetPlatform.android || usesIosAnki;
});

/// Manages the persisted AnkiDroid configuration.
class AnkidroidConfigNotifier extends Notifier<AnkidroidConfig> {
  bool _hasLoadedPersistedSettings = false;

  @override
  AnkidroidConfig build() => const AnkidroidConfig();

  /// Load persisted config from storage (called once at startup).
  Future<void> loadPersistedSettings() async {
    if (_hasLoadedPersistedSettings) return;
    _hasLoadedPersistedSettings = true;

    final json = await ref
        .read(appSettingsStorageProvider)
        .loadAnkidroidConfig();
    final config = AnkidroidConfig.decode(json);
    if (config != null) {
      state = config;
    }
  }

  /// Update and persist the entire config.
  void setConfig(AnkidroidConfig config) {
    state = config;
    unawaited(
      ref.read(appSettingsStorageProvider).saveAnkidroidConfig(config.encode()),
    );
  }

  /// Update the selected model and reset field mapping.
  void setModel(int modelId, String modelName, List<String> fields) {
    final mapping = {for (final f in fields) f: 'empty'};
    setConfig(
      state.copyWith(
        modelId: modelId,
        modelName: modelName,
        fieldMapping: mapping,
        ankiFieldNames: fields,
      ),
    );
  }

  /// Refresh the cached field order after a successful getFieldList. Anki is
  /// the source of truth for field order; lists fetched for a model other
  /// than the configured one (e.g. browsed in the picker) are ignored.
  void setAnkiFieldNames(int modelId, List<String> fields) {
    if (modelId != state.modelId ||
        fields.isEmpty ||
        listEquals(fields, state.ankiFieldNames)) {
      return;
    }
    setConfig(state.copyWith(ankiFieldNames: fields));
  }

  /// Update the default deck.
  void setDeck(int deckId, String deckName) {
    setConfig(state.copyWith(deckId: deckId, deckName: deckName));
  }

  /// Update a single field mapping.
  void setFieldMapping(String ankiField, String appDataSource) {
    final updated = Map<String, String>.from(state.fieldMapping);
    updated[ankiField] = appDataSource;
    setConfig(state.copyWith(fieldMapping: updated));
  }

  /// Drop the mapping for a field that no longer exists in Anki.
  void removeFieldMapping(String ankiField) {
    final updated = Map<String, String>.from(state.fieldMapping)
      ..remove(ankiField);
    setConfig(state.copyWith(fieldMapping: updated));
  }

  /// Update the default tags.
  void setTags(List<String> tags) {
    setConfig(state.copyWith(tags: tags));
  }

  /// Update the AnkiConnect address (iOS).
  void setAnkiConnectUrl(String url) {
    setConfig(state.copyWith(ankiConnectUrl: url));
  }

  /// Switch the iOS backend; each backend keeps its own selection.
  void setUseAnkiMobile(bool value) {
    setConfig(state.withUseAnkiMobile(value));
  }

  /// Save the names typed for AnkiMobile and select the synthetic note type
  /// and deck made from them. Fields that kept their name keep their mapping.
  void setAnkiMobile(String noteType, String deck, List<String> fields) {
    setConfig(
      state.copyWith(
        ankiMobileNoteType: noteType,
        ankiMobileDeck: deck,
        ankiMobileFields: fields,
        modelId: AnkiMobileService.syntheticId,
        modelName: noteType,
        deckId: AnkiMobileService.syntheticId,
        deckName: deck,
        ankiFieldNames: fields,
        fieldMapping: {
          for (final f in fields) f: state.fieldMapping[f] ?? 'empty',
        },
      ),
    );
  }
}

/// Provider for AnkiDroid configuration.
final ankidroidConfigProvider =
    NotifierProvider<AnkidroidConfigNotifier, AnkidroidConfig>(
      AnkidroidConfigNotifier.new,
    );
