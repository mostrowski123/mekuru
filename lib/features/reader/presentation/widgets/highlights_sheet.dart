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
              context.l10n.readerHighlightsTooltip,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: highlightsAsync.when(
              data: (highlights) {
                if (highlights.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        context.l10n.readerNoHighlightsYet,
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
                      onDelete: () =>
                          _deleteHighlight(ref, highlight, onRemoveHighlight),
                      onEditNote: () => showHighlightNoteEditor(
                        context,
                        highlightId: highlight.id,
                        note: highlight.userNote,
                      ),
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
}

/// Opens the note editor for highlight [highlightId], filled with [note].
/// Save stores the text as its note; Cancel leaves the highlight as it was.
Future<void> showHighlightNoteEditor(
  BuildContext context, {
  required int highlightId,
  String note = '',
}) {
  // Resolved before the dialog opens: the sheet can unmount while it's up.
  final container = ProviderScope.containerOf(context, listen: false);
  final controller = TextEditingController(text: note);
  return showDialog(
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
            container
                .read(highlightRepositoryProvider)
                .updateHighlightNote(highlightId, controller.text);
            Navigator.pop(context);
          },
          child: Text(context.l10n.commonSave),
        ),
      ],
    ),
  );
}

void _deleteHighlight(
  WidgetRef ref,
  Highlight highlight,
  void Function(String cfiRange)? onRemoveHighlight,
) {
  ref.read(highlightRepositoryProvider).deleteHighlight(highlight.id);
  onRemoveHighlight?.call(highlight.cfiRange);
}

/// Bottom sheet for the highlight drawn at [cfiRange], tapped on the page:
/// its text and note, with actions to edit the note or delete it.
/// [onRemoveHighlight] removes the drawn highlight, as for [HighlightsSheet].
class HighlightDetailsSheet extends ConsumerWidget {
  final int bookId;
  final String cfiRange;
  final void Function(String cfiRange)? onRemoveHighlight;

  const HighlightDetailsSheet({
    super.key,
    required this.bookId,
    required this.cfiRange,
    this.onRemoveHighlight,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watched, so a note saved from here shows at once.
    final highlight = ref
        .watch(highlightsForBookProvider(bookId))
        .value
        ?.where((h) => h.cfiRange == cfiRange)
        .firstOrNull;
    if (highlight == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final hasNote = highlight.userNote.isNotEmpty;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 4,
                  height: 24,
                  margin: const EdgeInsets.only(right: 12),
                  color: HighlightColor.fromName(highlight.color).color,
                ),
                Expanded(
                  child: Text(
                    highlight.selectedText,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            if (hasNote) ...[
              const SizedBox(height: 12),
              Text(
                highlight.userNote,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 8),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline),
                  label: Text(l10n.commonDelete),
                  onPressed: () {
                    _deleteHighlight(ref, highlight, onRemoveHighlight);
                    Navigator.pop(context);
                  },
                ),
                TextButton.icon(
                  icon: const Icon(Icons.edit_note),
                  label: Text(
                    hasNote ? l10n.readerEditNoteTitle : l10n.readerAddNote,
                  ),
                  onPressed: () => showHighlightNoteEditor(
                    context,
                    highlightId: highlight.id,
                    note: highlight.userNote,
                  ),
                ),
              ],
            ),
          ],
        ),
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
