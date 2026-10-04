import 'package:flutter/material.dart';
import 'package:mekuru/l10n/l10n.dart';

/// Asks whether to delete the dictionary called [name] and all its entries.
/// True only when the user picks Delete.
Future<bool> confirmDeleteDictionary(BuildContext context, String name) async {
  final l10n = context.l10n;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.dictionaryManagerDeleteTitle),
      content: Text(l10n.dictionaryManagerDeleteBody(name: name)),
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
  return confirmed == true;
}
