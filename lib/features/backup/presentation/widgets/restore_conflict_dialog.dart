import 'package:flutter/material.dart';
import 'package:mekuru/features/backup/data/services/restore_service.dart';

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

    return AlertDialog(
      title: const Text('Conflicting Books'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The following books already have reading data. '
              'Select which to overwrite with backup data:',
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
                      '${conflict.backupEntry.bookType.toUpperCase()} '
                      '- ${(conflict.backupEntry.readProgress * 100).round()}% in backup',
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
          child: const Text('Skip All'),
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
                ? 'Done'
                : 'Overwrite ${_selectedIndices.length}',
          ),
        ),
      ],
    );
  }
}
