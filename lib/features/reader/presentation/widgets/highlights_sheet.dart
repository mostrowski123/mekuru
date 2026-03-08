import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/reader/data/models/highlight_color.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/l10n/l10n.dart';

/// Bottom sheet listing all highlights for a book.
///
/// [onNavigate] is called when the user taps a highlight to jump to it.
/// [onRemoveHighlight] is called to remove the visual highlight in the EPUB.
class HighlightsSheet extends ConsumerWidget {
  final int bookId;
  final void Function(String cfiRange)? onNavigate;
  final void Function(String cfiRange)? onRemoveHighlight;

  const HighlightsSheet({
    super.key,
    required this.bookId,
    this.onNavigate,
    this.onRemoveHighlight,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final highlightsAsync = ref.watch(highlightsForBookProvider(bookId));

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (context, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Highlights',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: highlightsAsync.when(
              data: (highlights) {
                if (highlights.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'No highlights yet.\nSelect text while reading to add one.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  controller: scrollController,
                  itemCount: highlights.length,
                  itemBuilder: (context, index) {
                    final highlight = highlights[index];
                    return _HighlightTile(
                      highlight: highlight,
                      onTap: () {
                        if (onNavigate != null) {
                          Navigator.pop(context);
                          onNavigate!(highlight.cfiRange);
                        }
                      },
                      onDelete: () => _deleteHighlight(ref, highlight),
                      onEditNote: () =>
                          _editHighlightNote(context, ref, highlight),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(context.l10n.commonErrorWithDetails(details: '$e')),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _deleteHighlight(WidgetRef ref, Highlight highlight) {
    ref.read(highlightRepositoryProvider).deleteHighlight(highlight.id);
    onRemoveHighlight?.call(highlight.cfiRange);
  }

  void _editHighlightNote(
    BuildContext context,
    WidgetRef ref,
    Highlight highlight,
  ) {
    final controller = TextEditingController(text: highlight.userNote);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.readerEditNoteTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: context.l10n.readerAddNoteHint,
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () {
              ref
                  .read(highlightRepositoryProvider)
                  .updateHighlightNote(highlight.id, controller.text);
              Navigator.pop(context);
            },
            child: Text(context.l10n.commonSave),
          ),
        ],
      ),
    );
  }
}

class _HighlightTile extends StatelessWidget {
  final Highlight highlight;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onEditNote;

  const _HighlightTile({
    required this.highlight,
    required this.onTap,
    required this.onDelete,
    required this.onEditNote,
  });

  @override
  Widget build(BuildContext context) {
    final color = HighlightColor.fromName(highlight.color);
    final d = highlight.dateAdded;
    final dateStr =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final hasNote = highlight.userNote.isNotEmpty;

    return Dismissible(
      key: ValueKey(highlight.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => onDelete(),
      child: ListTile(
        leading: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color.color, shape: BoxShape.circle),
        ),
        title: Text(
          highlight.selectedText,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(dateStr),
            if (hasNote)
              Text(
                highlight.userNote,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        isThreeLine: hasNote,
        onTap: onTap,
        onLongPress: onEditNote,
      ),
    );
  }
}
