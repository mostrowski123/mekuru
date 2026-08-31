import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/ankidroid/data/models/ankidroid_config.dart';
import 'package:mekuru/features/ankidroid/data/services/anki_field_mapper.dart';
import 'package:mekuru/features/ankidroid/presentation/providers/ankidroid_providers.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/utils/haptics.dart';
import 'package:mekuru/shared/widgets/settings/settings_rows.dart';

/// Settings screen for configuring AnkiDroid integration.
///
/// Lets users select a note type, deck, default tags, and map Anki fields
/// to app data sources.
class AnkidroidSettingsScreen extends ConsumerStatefulWidget {
  const AnkidroidSettingsScreen({super.key});

  @override
  ConsumerState<AnkidroidSettingsScreen> createState() =>
      _AnkidroidSettingsScreenState();
}

class _AnkidroidSettingsScreenState
    extends ConsumerState<AnkidroidSettingsScreen> {
  bool _isLoading = true;
  String? _error;

  Map<int, String> _models = {};
  Map<int, String> _decks = {};
  List<String> _currentModelFields = [];

  late TextEditingController _tagsController;

  @override
  void initState() {
    super.initState();
    final config = ref.read(ankidroidConfigProvider);
    _tagsController = TextEditingController(text: config.tags.join(', '));
    _initAnkidroid();
  }

  @override
  void dispose() {
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _initAnkidroid() async {
    final service = ref.read(ankidroidServiceProvider);

    final granted = await service.requestPermission();
    if (!granted) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = context.l10n.ankidroidPermissionNotGrantedLong;
        });
      }
      return;
    }

    final initialized = await service.init();
    if (!initialized) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = context.l10n.ankidroidCouldNotConnectLong;
        });
      }
      return;
    }

    final modelId = ref.read(ankidroidConfigProvider).modelId;
    final (models, decks, fields) = await (
      service.getModelList(),
      service.getDeckList(),
      // No configured model: nothing to fetch, and an empty list must not
      // read as "the note type was deleted in Anki".
      modelId != null
          ? service.getFieldList(modelId)
          : Future<List<String>?>.value([]),
    ).wait;

    // Null means the query failed — show the connect error rather than
    // letting a hiccup masquerade as a deleted note type or deck.
    if (decks == null || fields == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = context.l10n.ankidroidCouldNotConnectLong;
        });
      }
      return;
    }

    _currentModelFields = fields;
    if (modelId != null) {
      ref
          .read(ankidroidConfigProvider.notifier)
          .setAnkiFieldNames(modelId, fields);
    }
    if (mounted) {
      setState(() {
        _isLoading = false;
        _models = models;
        _decks = decks;
      });
    }
  }

  void _saveTags() {
    final tags = _tagsController.text
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    ref.read(ankidroidConfigProvider.notifier).setTags(tags);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = ref.watch(ankidroidConfigProvider);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsAnkiDroidIntegrationTitle)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _buildError(theme)
          : _buildSettings(theme, config),
    );
  }

  Widget _buildError(ThemeData theme) {
    final l10n = context.l10n;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _error = null;
                });
                _initAnkidroid();
              },
              child: Text(l10n.commonRetry),
            ),
          ],
        ),
      ),
    );
  }

  /// Subtitle for the note-type / deck tiles: the configured name, painted
  /// as an error when the item no longer exists in Anki.
  Widget _missingAwareSubtitle(String? name, {required bool missing}) {
    final l10n = context.l10n;
    return missing
        ? Text(
            l10n.ankidroidMissingInAnki(name: name ?? ''),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          )
        : Text(name ?? l10n.commonNotSelected);
  }

  Widget _buildSettings(ThemeData theme, AnkidroidConfig config) {
    final l10n = context.l10n;

    return ListView(
      children: [
        // ── Note Type ──
        SettingsSectionHeader(title: l10n.ankidroidSettingsNoteTypeSection),
        ListTile(
          leading: Icon(Icons.note_outlined, color: theme.colorScheme.primary),
          title: Text(l10n.ankidroidSettingsNoteTypeTitle),
          subtitle: _missingAwareSubtitle(
            config.modelName,
            missing: config.modelId != null && _currentModelFields.isEmpty,
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showModelPicker(context),
        ),
        const Divider(),

        // ── Default Deck ──
        SettingsSectionHeader(title: l10n.ankidroidSettingsDefaultDeckSection),
        ListTile(
          leading: Icon(
            Icons.layers_outlined,
            color: theme.colorScheme.primary,
          ),
          title: Text(l10n.ankidroidSettingsTargetDeckTitle),
          subtitle: _missingAwareSubtitle(
            config.deckName,
            missing:
                config.deckId != null && !_decks.containsKey(config.deckId),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showDeckPicker(context),
        ),
        const Divider(),

        // ── Field Mapping ──
        if (config.modelId != null && _currentModelFields.isNotEmpty) ...[
          SettingsSectionHeader(
            title: l10n.ankidroidSettingsFieldMappingSection,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              l10n.ankidroidSettingsFieldMappingHelp,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          ..._currentModelFields.map((fieldName) {
            final currentMapping = config.fieldMapping[fieldName] ?? 'empty';
            final currentSource = AppDataSource.fromKey(currentMapping);
            return ListTile(
              title: Text(fieldName),
              subtitle: Text(currentSource.localizedLabel(l10n)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  _showFieldMappingPicker(context, fieldName, currentMapping),
            );
          }),
          // Mapped fields that were renamed or deleted in Anki. Anki is the
          // source of truth: tap to move the data source to a current field,
          // or remove the orphaned mapping.
          ...AnkiFieldMapper.staleMappedFields(
            ankiFieldNames: _currentModelFields,
            fieldMapping: config.fieldMapping,
          ).map((fieldName) {
            final source = AppDataSource.fromKey(
              config.fieldMapping[fieldName]!,
            );
            return ListTile(
              leading: Icon(
                Icons.warning_amber,
                color: theme.colorScheme.error,
              ),
              title: Text(
                fieldName,
                style: TextStyle(color: theme.colorScheme.error),
              ),
              subtitle: Text(
                l10n.ankidroidStaleFieldSubtitle(
                  source: source.localizedLabel(l10n),
                ),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: l10n.commonRemove,
                onPressed: () => ref
                    .read(ankidroidConfigProvider.notifier)
                    .removeFieldMapping(fieldName),
              ),
              onTap: () => _showReassignPicker(context, fieldName, source),
            );
          }),
          const Divider(),
        ],

        // ── Default Tags ──
        SettingsSectionHeader(title: l10n.ankidroidSettingsDefaultTagsSection),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            l10n.ankidroidSettingsDefaultTagsHelp,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            controller: _tagsController,
            decoration: InputDecoration(
              border: OutlineInputBorder(),
              hintText: l10n.ankidroidTagsHint,
              isDense: true,
            ),
            onChanged: (_) => _saveTags(),
          ),
        ),
      ],
    );
  }

  void _showModelPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                sheetContext.l10n.ankidroidSettingsSelectNoteType,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: _models.entries.map((entry) {
                  final isSelected =
                      ref.read(ankidroidConfigProvider).modelId == entry.key;
                  return ListTile(
                    title: Text(entry.value),
                    trailing: isSelected
                        ? Icon(
                            Icons.check,
                            color: Theme.of(context).colorScheme.primary,
                          )
                        : null,
                    onTap: () async {
                      AppHaptics.medium();
                      Navigator.pop(sheetContext);
                      final fields = await ref
                          .read(ankidroidServiceProvider)
                          .getFieldList(entry.key);
                      // Failed query: keep the previous selection rather
                      // than resetting the mapping to nothing.
                      if (fields == null) return;
                      ref
                          .read(ankidroidConfigProvider.notifier)
                          .setModel(entry.key, entry.value, fields);
                      if (mounted) {
                        setState(() => _currentModelFields = fields);
                      }
                    },
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeckPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                sheetContext.l10n.ankidroidSettingsSelectDeck,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: _decks.entries.map((entry) {
                  final isSelected =
                      ref.read(ankidroidConfigProvider).deckId == entry.key;
                  return ListTile(
                    title: Text(entry.value),
                    trailing: isSelected
                        ? Icon(
                            Icons.check,
                            color: Theme.of(context).colorScheme.primary,
                          )
                        : null,
                    onTap: () {
                      AppHaptics.medium();
                      ref
                          .read(ankidroidConfigProvider.notifier)
                          .setDeck(entry.key, entry.value);
                      Navigator.pop(sheetContext);
                    },
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Moves the data source of a stale mapping onto one of the note type's
  /// current fields, then drops the stale entry.
  void _showReassignPicker(
    BuildContext context,
    String staleFieldName,
    AppDataSource source,
  ) {
    final l10n = context.l10n;
    final mapping = ref.read(ankidroidConfigProvider).fieldMapping;
    showSettingsOptionPickerSheet<String>(
      context: context,
      title: l10n.ankidroidReassignFieldTo(source: source.localizedLabel(l10n)),
      values: _currentModelFields,
      labelOf: (fieldName) => fieldName,
      subtitleOf: (fieldName) => AppDataSource.fromKey(
        mapping[fieldName] ?? AppDataSource.empty.key,
      ).localizedLabel(l10n),
      onSelected: (fieldName) {
        final notifier = ref.read(ankidroidConfigProvider.notifier);
        notifier
          ..setFieldMapping(fieldName, source.key)
          ..removeFieldMapping(staleFieldName);
      },
    );
  }

  void _showFieldMappingPicker(
    BuildContext context,
    String ankiFieldName,
    String currentKey,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                sheetContext.l10n.ankidroidSettingsMapFieldTo(
                  ankiFieldName: ankiFieldName,
                ),
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: AppDataSource.values.map((source) {
                  return ListTile(
                    title: Text(source.localizedLabel(sheetContext.l10n)),
                    trailing: currentKey == source.key
                        ? Icon(
                            Icons.check,
                            color: Theme.of(context).colorScheme.primary,
                          )
                        : null,
                    onTap: () {
                      AppHaptics.medium();
                      ref
                          .read(ankidroidConfigProvider.notifier)
                          .setFieldMapping(ankiFieldName, source.key);
                      Navigator.pop(sheetContext);
                    },
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
