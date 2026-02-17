import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/ankidroid/data/models/ankidroid_config.dart';
import 'package:mekuru/features/ankidroid/data/services/ankidroid_service.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';

/// Provider for the AnkiDroid service singleton.
final ankidroidServiceProvider = Provider<AnkidroidService>((ref) {
  final service = AnkidroidService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Whether the current platform supports AnkiDroid integration.
final ankidroidAvailableProvider = Provider<bool>((ref) {
  return defaultTargetPlatform == TargetPlatform.android;
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

    final json =
        await ref.read(appSettingsStorageProvider).loadAnkidroidConfig();
    final config = AnkidroidConfig.decode(json);
    if (config != null) {
      state = config;
    }
  }

  /// Update and persist the entire config.
  void setConfig(AnkidroidConfig config) {
    state = config;
    unawaited(
      ref
          .read(appSettingsStorageProvider)
          .saveAnkidroidConfig(config.encode()),
    );
  }

  /// Update the selected model and reset field mapping.
  void setModel(int modelId, String modelName, List<String> fields) {
    final mapping = {for (final f in fields) f: 'empty'};
    setConfig(state.copyWith(
      modelId: modelId,
      modelName: modelName,
      fieldMapping: mapping,
    ));
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

  /// Update the default tags.
  void setTags(List<String> tags) {
    setConfig(state.copyWith(tags: tags));
  }
}

/// Provider for AnkiDroid configuration.
final ankidroidConfigProvider =
    NotifierProvider<AnkidroidConfigNotifier, AnkidroidConfig>(
  AnkidroidConfigNotifier.new,
);
