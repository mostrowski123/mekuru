import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/ankidroid/data/models/anki_note_data.dart';
import 'package:mekuru/features/ankidroid/data/services/anki_field_mapper.dart';
import 'package:mekuru/features/ankidroid/presentation/providers/ankidroid_providers.dart';
import 'package:mekuru/features/ankidroid/presentation/screens/ankidroid_settings_screen.dart';
import 'package:mekuru/l10n/l10n.dart';

/// Screen for reviewing and sending a note to AnkiDroid.
///
/// Pops with `true` on success, `null` on cancel.
class AnkiCardCreationScreen extends ConsumerStatefulWidget {
  const AnkiCardCreationScreen({super.key, required this.noteData});

  final AnkiNoteData noteData;

  @override
  ConsumerState<AnkiCardCreationScreen> createState() =>
      _AnkiCardCreationScreenState();
}

class _AnkiCardCreationScreenState
    extends ConsumerState<AnkiCardCreationScreen> {
  final List<TextEditingController> _controllers = [];
  late TextEditingController _tagsController;
  List<String> _fieldNames = [];
  bool _isLoading = true;
  bool _isSending = false;
  String? _error;

  int? _selectedDeckId;
  String? _selectedDeckName;
  Map<int, String> _decks = {};

  @override
  void initState() {
    super.initState();
    final config = ref.read(ankidroidConfigProvider);
    _tagsController = TextEditingController(text: config.tags.join(', '));
    _loadFields();
  }

  Future<void> _loadFields() async {
    final config = ref.read(ankidroidConfigProvider);

    final service = ref.read(ankidroidServiceProvider);
    final granted = await service.requestPermission();
    if (!granted) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = context.l10n.ankidroidPermissionNotGrantedShort;
        });
      }
      return;
    }

    final initialized = await service.init();
    if (!initialized) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = context.l10n.ankidroidCouldNotConnectShort;
        });
      }
      return;
    }

    _fieldNames = await service.getFieldList(config.modelId!);
    _decks = await service.getDeckList();
    _selectedDeckId = config.deckId;
    _selectedDeckName = config.deckName;

    final values = AnkiFieldMapper.resolveFields(
      ankiFieldNames: _fieldNames,
      fieldMapping: config.fieldMapping,
      noteData: widget.noteData,
    );

    for (final value in values) {
      _controllers.add(TextEditingController(text: value));
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  /// Reload fields after returning from settings (model or mapping may have
  /// changed).
  Future<void> _reloadFields() async {
    final config = ref.read(ankidroidConfigProvider);
    if (config.modelId == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final service = ref.read(ankidroidServiceProvider);
    final fields = await service.getFieldList(config.modelId!);
    final decks = await service.getDeckList();

    // Dispose old controllers
    for (final c in _controllers) {
      c.dispose();
    }
    _controllers.clear();

    _fieldNames = fields;
    _decks = decks;
    _selectedDeckId = config.deckId;
    _selectedDeckName = config.deckName;

    final values = AnkiFieldMapper.resolveFields(
      ankiFieldNames: _fieldNames,
      fieldMapping: config.fieldMapping,
      noteData: widget.noteData,
    );

    for (final value in values) {
      _controllers.add(TextEditingController(text: value));
    }

    // Update tags from config
    _tagsController.text = config.tags.join(', ');

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _sendNote() async {
    final config = ref.read(ankidroidConfigProvider);
    if (config.modelId == null || _selectedDeckId == null) return;

    setState(() {
      _isSending = true;
      _error = null;
    });

    final fields = _controllers.map((c) => c.text).toList();
    final tags = _tagsController.text
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    final service = ref.read(ankidroidServiceProvider);
    final noteId = await service.addNote(
      modelId: config.modelId!,
      deckId: _selectedDeckId!,
      fields: fields,
      tags: tags,
    );

    if (mounted) {
      if (noteId != null) {
        // Success snackbar is shown by the caller (DictionaryEntryCard)
        // via the global ScaffoldMessenger so it appears on top of the
        // lookup sheet.
        Navigator.pop(context, true);
      } else {
        final errorMsg = context.l10n.ankidroidFailedToAddNote;
        setState(() {
          _isSending = false;
          _error = errorMsg;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            duration: Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.noteData.expression),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: l10n.ankidroidCardSettingsTooltip,
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AnkidroidSettingsScreen(),
                ),
              );
              if (mounted) _reloadFields();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _controllers.isEmpty
          ? _buildErrorState(theme)
          : _buildForm(theme),
    );
  }

  Widget _buildErrorState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(ThemeData theme) {
    final l10n = context.l10n;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Deck selector
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.layers_outlined,
                  color: theme.colorScheme.primary,
                ),
                title: Text(l10n.ankidroidCardDeckTitle),
                subtitle: Text(_selectedDeckName ?? l10n.commonNotSelected),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showDeckPicker,
              ),
              const Divider(),
              const SizedBox(height: 4),

              // Error message
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: theme.colorScheme.error,
                      fontSize: 13,
                    ),
                  ),
                ),

              // Field editors
              for (var i = 0; i < _fieldNames.length; i++) ...[
                Text(_fieldNames[i], style: theme.textTheme.labelMedium),
                const SizedBox(height: 4),
                TextField(
                  controller: _controllers[i],
                  maxLines: null,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Tags (at the bottom)
              const SizedBox(height: 4),
              Text(
                l10n.ankidroidCardTagsTitle,
                style: theme.textTheme.labelMedium,
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _tagsController,
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: l10n.ankidroidTagsHint,
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
        // Send button
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isSending ? null : _sendNote,
              child: _isSending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.ankidroidCardAddToAnki),
            ),
          ),
        ),
      ],
    );
  }

  void _showDeckPicker() {
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
                  return ListTile(
                    title: Text(entry.value),
                    trailing: _selectedDeckId == entry.key
                        ? Icon(
                            Icons.check,
                            color: Theme.of(context).colorScheme.primary,
                          )
                        : null,
                    onTap: () {
                      setState(() {
                        _selectedDeckId = entry.key;
                        _selectedDeckName = entry.value;
                      });
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
