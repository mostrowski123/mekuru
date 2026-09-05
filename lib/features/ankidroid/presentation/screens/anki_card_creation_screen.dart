import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/ankidroid/data/models/anki_note_data.dart';
import 'package:mekuru/features/ankidroid/data/models/ankidroid_config.dart';
import 'package:mekuru/features/ankidroid/data/services/anki_field_mapper.dart';
import 'package:mekuru/features/ankidroid/presentation/providers/ankidroid_providers.dart';
import 'package:mekuru/features/ankidroid/presentation/screens/ankidroid_settings_screen.dart';
import 'package:mekuru/features/stats/presentation/providers/stats_providers.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/utils/app_routes.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Screen for reviewing and sending a note to AnkiDroid.
///
/// Pops with `true` on success, `null` on cancel.
class AnkiCardCreationScreen extends ConsumerStatefulWidget {
  const AnkiCardCreationScreen({
    super.key,
    required this.noteData,
    this.saveSource = 'other',
  });

  final AnkiNoteData noteData;

  /// Surface the card was created from, recorded on the word event
  /// (`'epub'`, `'manga'`, or `'other'` for non-reader surfaces).
  final String saveSource;

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
  Map<int, String> _decks = {};

  String? get _selectedDeckName => _decks[_selectedDeckId];

  bool _duplicateInDeck = false;
  int _duplicateCheckGeneration = 0;

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

    final (fields, decks) = await (
      service.getFieldList(config.modelId!),
      service.getDeckList(),
    ).wait;
    _applyAnkiState(config, fields, decks);
  }

  /// Reload fields after returning from settings (model or mapping may have
  /// changed).
  Future<void> _reloadFields() async {
    if (ref.read(ankidroidConfigProvider).modelId == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    await _loadFields();
  }

  /// Applies freshly fetched Anki state. Anki is the source of truth — but
  /// only a successful query can prove something is gone: null [fields] or
  /// [decks] mean the query failed and must not present as a deletion. An
  /// empty field list means the configured note type no longer exists, and a
  /// configured deck missing from [decks] is deselected.
  void _applyAnkiState(
    AnkidroidConfig config,
    List<String>? fields,
    Map<int, String>? decks,
  ) {
    for (final c in _controllers) {
      c.dispose();
    }
    _controllers.clear();
    _fieldNames = [];

    if (fields == null || decks == null || fields.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = fields == null || decks == null
              ? context.l10n.ankidroidCouldNotConnectShort
              : context.l10n.ankidroidNoteTypeMissing;
        });
      }
      return;
    }

    _fieldNames = fields;
    ref
        .read(ankidroidConfigProvider.notifier)
        .setAnkiFieldNames(config.modelId!, fields);
    _decks = decks;
    _selectedDeckId = decks.containsKey(config.deckId) ? config.deckId : null;
    _tagsController.text = config.tags.join(', ');

    final values = AnkiFieldMapper.resolveFields(
      ankiFieldNames: _fieldNames,
      fieldMapping: config.fieldMapping,
      noteData: widget.noteData,
    );

    for (final value in values) {
      _controllers.add(TextEditingController(text: value));
    }

    unawaited(_checkDuplicateInDeck());

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  /// Re-check whether a note with the same first field already exists in
  /// the currently selected deck. Generation-guarded so a slow check for a
  /// previously selected deck can't overwrite the current deck's result.
  Future<void> _checkDuplicateInDeck() async {
    final generation = ++_duplicateCheckGeneration;
    final modelId = ref.read(ankidroidConfigProvider).modelId;
    final deckId = _selectedDeckId;
    final firstField = _controllers.isNotEmpty ? _controllers.first.text : '';
    if (modelId == null || deckId == null || firstField.trim().isEmpty) {
      if (mounted) setState(() => _duplicateInDeck = false);
      return;
    }

    final exists = await ref
        .read(ankidroidServiceProvider)
        .hasDuplicateInDeck(
          modelId: modelId,
          deckId: deckId,
          firstFieldValue: firstField,
        );

    if (mounted && generation == _duplicateCheckGeneration) {
      setState(() => _duplicateInDeck = exists);
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
    // Read before the await so the provider is still reachable even if this
    // screen is disposed while addNote is in flight.
    final statsRepository = ref.read(statsRepositoryProvider);
    int? noteId;
    Object? sendError;
    try {
      noteId = await service.addNote(
        modelId: config.modelId!,
        deckId: _selectedDeckId!,
        fields: fields,
        tags: tags,
      );
    } catch (e) {
      sendError = e;
    }

    if (noteId != null) {
      logUsage('anki.card_sent', attrs: {'result': 'ok'});
      try {
        await statsRepository.insertWordEvent(
          kind: 'anki',
          expression: widget.noteData.expression,
          source: widget.saveSource,
        );
      } catch (e, st) {
        await Sentry.captureException(e, stackTrace: st);
      }
    } else {
      logFailure(
        'anki.card_sent',
        sendError ?? StateError('addNote returned null'),
      );
    }

    if (mounted) {
      if (noteId != null) {
        // Success snackbar is shown by the caller via the global
        // ScaffoldMessenger so it appears on top of the lookup sheet.
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
            onPressed: _openSettings,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _controllers.isEmpty
          ? _buildErrorState(theme)
          : _buildForm(
              theme,
              AnkiFieldMapper.staleMappedFields(
                ankiFieldNames: _fieldNames,
                fieldMapping: ref.watch(ankidroidConfigProvider).fieldMapping,
              ),
            ),
    );
  }

  Future<void> _openSettings() async {
    await Navigator.of(
      context,
    ).push(namedRoute('anki_settings', (_) => const AnkidroidSettingsScreen()));
    if (mounted) _reloadFields();
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
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: _openSettings,
              child: Text(context.l10n.ankidroidCardSettingsTooltip),
            ),
          ],
        ),
      ),
    );
  }

  /// Shared shape for the inline notices (stale mapping, duplicate note).
  Widget _inlineBanner({
    required IconData icon,
    required Color background,
    required Color foreground,
    required String message,
    VoidCallback? onTap,
  }) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(icon, size: 18, color: foreground),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: foreground),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForm(ThemeData theme, List<String> staleMappedFields) {
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

              // Mapped fields that were renamed or deleted in Anki.
              if (staleMappedFields.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _inlineBanner(
                    icon: Icons.warning_amber,
                    background: theme.colorScheme.errorContainer,
                    foreground: theme.colorScheme.onErrorContainer,
                    message: l10n.ankidroidStaleMappingBanner(
                      fields: staleMappedFields.map((f) => '"$f"').join(', '),
                    ),
                    onTap: _openSettings,
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
        // Non-blocking duplicate warning for the selected deck.
        if (_duplicateInDeck)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _inlineBanner(
              icon: Icons.info_outline,
              background: theme.colorScheme.tertiaryContainer,
              foreground: theme.colorScheme.onTertiaryContainer,
              message: l10n.ankidroidAlreadyInDeck(
                deck: _selectedDeckName ?? '',
              ),
            ),
          ),
        // Send button
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isSending || _selectedDeckId == null
                  ? null
                  : _sendNote,
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
                      setState(() => _selectedDeckId = entry.key);
                      unawaited(_checkDuplicateInDeck());
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
