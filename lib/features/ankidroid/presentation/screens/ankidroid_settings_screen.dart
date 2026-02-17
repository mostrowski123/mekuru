import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/ankidroid/data/models/ankidroid_config.dart';
import 'package:mekuru/features/ankidroid/data/services/anki_field_mapper.dart';
import 'package:mekuru/features/ankidroid/presentation/providers/ankidroid_providers.dart';
import 'package:mekuru/shared/utils/haptics.dart';

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
          _error = 'AnkiDroid permission not granted. '
              'Make sure AnkiDroid is installed and try again.';
        });
      }
      return;
    }

    final initialized = await service.init();
    if (!initialized) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Could not connect to AnkiDroid. '
              'Make sure AnkiDroid is installed and running.';
        });
      }
      return;
    }

    final models = await service.getModelList();
    final decks = await service.getDeckList();

    final config = ref.read(ankidroidConfigProvider);
    if (config.modelId != null) {
      _currentModelFields = await service.getFieldList(config.modelId!);
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

    return Scaffold(
      appBar: AppBar(title: const Text('AnkiDroid Integration')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError(theme)
              : _buildSettings(theme, config),
    );
  }

  Widget _buildError(ThemeData theme) {
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
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettings(ThemeData theme, AnkidroidConfig config) {
    return ListView(
      children: [
        // ── Note Type ──
        _SectionHeader(title: 'Note Type'),
        ListTile(
          leading:
              Icon(Icons.note_outlined, color: theme.colorScheme.primary),
          title: const Text('Anki Note Type'),
          subtitle: Text(config.modelName ?? 'Not selected'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showModelPicker(context),
        ),
        const Divider(),

        // ── Default Deck ──
        _SectionHeader(title: 'Default Deck'),
        ListTile(
          leading:
              Icon(Icons.layers_outlined, color: theme.colorScheme.primary),
          title: const Text('Target Deck'),
          subtitle: Text(config.deckName ?? 'Not selected'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showDeckPicker(context),
        ),
        const Divider(),

        // ── Field Mapping ──
        if (config.modelId != null && _currentModelFields.isNotEmpty) ...[
          _SectionHeader(title: 'Field Mapping'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'Map each Anki field to a data source from the app.',
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
              subtitle: Text(currentSource.displayName),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showFieldMappingPicker(
                context,
                fieldName,
                currentMapping,
              ),
            );
          }),
          const Divider(),
        ],

        // ── Default Tags ──
        _SectionHeader(title: 'Default Tags'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            'Comma-separated tags applied to every exported note.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            controller: _tagsController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'mekuru, japanese',
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
                'Select Note Type',
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
                        ? Icon(Icons.check,
                            color: Theme.of(context).colorScheme.primary)
                        : null,
                    onTap: () async {
                      AppHaptics.medium();
                      Navigator.pop(sheetContext);
                      final fields = await ref
                          .read(ankidroidServiceProvider)
                          .getFieldList(entry.key);
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
                'Select Deck',
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
                        ? Icon(Icons.check,
                            color: Theme.of(context).colorScheme.primary)
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
                'Map "$ankiFieldName" to:',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: AppDataSource.values.map((source) {
                  return ListTile(
                    title: Text(source.displayName),
                    trailing: currentKey == source.key
                        ? Icon(Icons.check,
                            color: Theme.of(context).colorScheme.primary)
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
