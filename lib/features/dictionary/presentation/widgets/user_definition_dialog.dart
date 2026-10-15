import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/l10n/l10n.dart';

/// Opens the form for the user's own definition: a new one for [term], or
/// [entry] to edit. True once saved.
Future<bool> showUserDefinitionDialog(
  BuildContext context, {
  String term = '',
  DictionaryEntry? entry,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _UserDefinitionDialog(term: term, entry: entry),
  );
  return saved == true;
}

/// Asks before deleting the user's own definition [entry]. True once
/// deleted.
Future<bool> confirmDeleteUserDefinition(
  BuildContext context,
  DictionaryEntry entry,
) async {
  final l10n = context.l10n;
  final repository = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(dictionaryRepositoryProvider);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.userDefinitionDeleteTitle(term: entry.expression)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
          ),
          child: Text(l10n.commonDelete),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;
  await repository.deleteUserDefinition(entry.id);
  logUsage('dictionary.user_definition_deleted');
  return true;
}

class _UserDefinitionDialog extends ConsumerStatefulWidget {
  const _UserDefinitionDialog({required this.term, this.entry});

  final String term;
  final DictionaryEntry? entry;

  @override
  ConsumerState<_UserDefinitionDialog> createState() =>
      _UserDefinitionDialogState();
}

class _UserDefinitionDialogState extends ConsumerState<_UserDefinitionDialog> {
  late final _term = TextEditingController(
    text: widget.entry?.expression ?? widget.term,
  );
  late final _reading = TextEditingController(text: widget.entry?.reading);
  late final _definition = TextEditingController(
    text: switch (widget.entry) {
      final entry? => DictionaryRepository.userDefinitionText(entry),
      null => '',
    },
  );
  bool _saving = false;

  bool get _canSave =>
      !_saving &&
      _term.text.trim().isNotEmpty &&
      _definition.text.trim().isNotEmpty;

  @override
  void dispose() {
    _term.dispose();
    _reading.dispose();
    _definition.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final repository = ref.read(dictionaryRepositoryProvider);
    final queryService = ref.read(dictionaryQueryServiceProvider);
    final entry = widget.entry;
    setState(() => _saving = true);
    try {
      if (entry == null) {
        await repository.addUserDefinition(
          term: _term.text,
          reading: _reading.text,
          definition: _definition.text,
        );
      } else {
        await repository.updateUserDefinition(
          entry.id,
          term: _term.text,
          reading: _reading.text,
          definition: _definition.text,
        );
      }
    } finally {
      // A failed save keeps the form and its text, so nothing is lost.
      if (mounted) setState(() => _saving = false);
    }
    queryService.invalidateMetasCache();
    logUsage(
      'dictionary.user_definition_saved',
      attrs: {'edit': entry != null},
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    void refresh(String _) => setState(() {});
    return AlertDialog(
      title: Text(
        widget.entry == null ? l10n.userDefinitionAdd : l10n.userDefinitionEdit,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _term,
              decoration: InputDecoration(
                labelText: l10n.userDefinitionTermLabel,
              ),
              onChanged: refresh,
            ),
            TextField(
              controller: _reading,
              decoration: InputDecoration(
                labelText: l10n.userDefinitionReadingLabel,
              ),
            ),
            TextField(
              controller: _definition,
              autofocus: true,
              minLines: 3,
              maxLines: 8,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                labelText: l10n.userDefinitionDefinitionLabel,
              ),
              onChanged: refresh,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: _canSave ? _save : null,
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }
}
