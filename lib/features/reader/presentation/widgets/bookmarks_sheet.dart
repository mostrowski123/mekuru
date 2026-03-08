import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/l10n/l10n.dart';

/// Bottom sheet listing all bookmarks for a book.
///
/// [onNavigate] is called when the user taps a bookmark to jump to it.
/// If null, navigation is disabled (used from the library screen).
class BookmarksSheet extends ConsumerWidget {
  final int bookId;
  final void Function(String cfi)? onNavigate;
  final VoidCallback? onBookmarkDeleted;

  const BookmarksSheet({
    super.key,
    required this.bookId,
    this.onNavigate,
    this.onBookmarkDeleted,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookmarksAsync = ref.watch(bookmarksForBookProvider(bookId));
    final l10n = context.l10n;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (context, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              l10n.readerBookmarksTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: bookmarksAsync.when(
              data: (bookmarks) {
                if (bookmarks.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        l10n.readerNoBookmarksYet,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  controller: scrollController,
                  itemCount: bookmarks.length,
                  itemBuilder: (context, index) {
                    final bookmark = bookmarks[index];
                    return _BookmarkTile(
                      bookmark: bookmark,
                      onTap: () {
                        if (onNavigate != null) {
                          Navigator.pop(context);
                          onNavigate!(bookmark.cfi);
                        }
                      },
                      onDelete: () => _deleteBookmark(context, ref, bookmark),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(l10n.commonErrorWithDetails(details: '$e')),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _deleteBookmark(BuildContext context, WidgetRef ref, Bookmark bookmark) {
    ref.read(bookmarkRepositoryProvider).deleteBookmark(bookmark.id);
    onBookmarkDeleted?.call();
  }
}

class _BookmarkTile extends StatelessWidget {
  final Bookmark bookmark;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _BookmarkTile({
    required this.bookmark,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final d = bookmark.dateAdded;
    final dateStr =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final progressStr = '${(bookmark.progress * 100).toInt()}%';

    return Dismissible(
      key: ValueKey(bookmark.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => onDelete(),
      child: ListTile(
        leading: const Icon(Icons.bookmark, color: Colors.amber),
        title: Text(
          context.l10n.readerBookmarkProgressDate(
            progress: progressStr,
            date: dateStr,
          ),
        ),
        subtitle: bookmark.chapterTitle.isNotEmpty
            ? Text(
                bookmark.chapterTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            : null,
        onTap: onTap,
      ),
    );
  }
}
