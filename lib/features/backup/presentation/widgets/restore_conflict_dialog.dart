import 'package:flutter/material.dart';
import 'package:mekuru/features/backup/data/services/restore_service.dart';
import 'package:mekuru/l10n/l10n.dart';

/// Batch modal listing all conflicting books with checkboxes.
/// Returns the list of conflicts the user chose to overwrite, or null if cancelled.
class RestoreConflictDialog extends StatefulWidget {
  final List<BookRestoreConflict> conflicts;

  const RestoreConflictDialog({super.key, required this.conflicts});

  /// Show the dialog and return selected conflicts to overwrite (or null).
  static Future<List<BookRestoreConflict>?> show(
    BuildContext context,
    List<BookRestoreConflict> conflicts,
  ) {
    return showDialog<List<BookRestoreConflict>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RestoreConflictDialog(conflicts: conflicts),
    );
  }

  @override
  State<RestoreConflictDialog> createState() => _RestoreConflictDialogState();
}

class _RestoreConflictDialogState extends State<RestoreConflictDialog> {
  late final Set<int> _selectedIndices;

  @override
  void initState() {
    super.initState();
    // Select all by default
    _selectedIndices = Set<int>.from(
      List.generate(widget.conflicts.length, (i) => i),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return AlertDialog(
      title: Text(l10n.backupConflictDialogTitle),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.backupConflictDialogBody,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.conflicts.length,
                itemBuilder: (context, index) {
                  final conflict = widget.conflicts[index];
                  final isSelected = _selectedIndices.contains(index);

                  return CheckboxListTile(
                    value: isSelected,
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          _selectedIndices.add(index);
                        } else {
                          _selectedIndices.remove(index);
                        }
                      });
                    },
                    title: Text(
                      conflict.existingBook.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      l10n.backupConflictEntrySubtitle(
                        bookType: _bookTypeLabel(
                          context,
                          conflict.backupEntry.bookType,
                        ),
                        progress: (conflict.backupEntry.readProgress * 100)
                            .round(),
                      ),
                      style: theme.textTheme.bodySmall,
                    ),
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(l10n.backupConflictSkipAll),
        ),
        TextButton(
          onPressed: () {
            final selected = _selectedIndices
                .map((i) => widget.conflicts[i])
                .toList();
            Navigator.of(context).pop(selected);
          },
          child: Text(
            _selectedIndices.isEmpty
                ? l10n.commonDone
                : l10n.backupConflictOverwriteSelected(
                    count: _selectedIndices.length,
                  ),
          ),
        ),
      ],
    );
  }

  String _bookTypeLabel(BuildContext context, String bookType) {
    return switch (bookType.toLowerCase()) {
      'manga' => context.l10n.backupBookTypeManga,
      'epub' => context.l10n.backupBookTypeEpub,
      _ => bookType.toUpperCase(),
    };
  }
}
