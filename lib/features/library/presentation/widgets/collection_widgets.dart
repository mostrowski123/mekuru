import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/library/presentation/providers/library_providers.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/utils/haptics.dart';

/// Opens the membership sheet for [book].
Future<void> showCollectionAssignSheet(BuildContext context, Book book) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (_) => CollectionAssignSheet(book: book),
  );
}

/// Checkbox list of collections for one book. Toggles write immediately.
class CollectionAssignSheet extends ConsumerWidget {
  const CollectionAssignSheet({super.key, required this.book});

  final Book book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collections = ref.watch(collectionsProvider).value ?? const [];
    final memberIds =
        ref
            .watch(bookCollectionsProvider)
            .value
            ?.where((m) => m.bookId == book.id)
            .map((m) => m.collectionId)
            .toSet() ??
        const <int>{};

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              book.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(context.l10n.libraryAddToCollectionAction),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final collection in collections)
                  CheckboxListTile(
                    value: memberIds.contains(collection.id),
                    title: Text(collection.name),
                    onChanged: (checked) {
                      AppHaptics.light();
                      final next = {...memberIds};
                      if (checked ?? false) {
                        next.add(collection.id);
                      } else {
                        next.remove(collection.id);
                      }
                      ref
                          .read(collectionRepositoryProvider)
                          .setBookCollections(book.id, next);
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.add),
                  title: Text(context.l10n.libraryNewCollectionAction),
                  onTap: () async {
                    AppHaptics.light();
                    final name = await _promptName(
                      context,
                      title: context.l10n.libraryNewCollectionAction,
                    );
                    if (name == null || name.isEmpty) return;
                    final repo = ref.read(collectionRepositoryProvider);
                    final id = await repo.createCollection(name);
                    // The new collection also gets this book — that is what
                    // the user came here to do.
                    await repo.setBookCollections(book.id, {...memberIds, id});
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Name-entry dialog shared by create and rename. Pops the trimmed name,
/// or null when cancelled.
Future<String?> _promptName(
  BuildContext context, {
  required String title,
  String initial = '',
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: context.l10n.libraryCollectionNameLabel,
          border: const OutlineInputBorder(),
        ),
        textCapitalization: TextCapitalization.words,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(context.l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
          child: Text(context.l10n.commonSave),
        ),
      ],
    ),
  );
}

/// Opens the rename/delete sheet for [collection].
Future<void> showCollectionManageSheet(
  BuildContext context,
  Collection collection,
) {
  return showModalBottomSheet(
    context: context,
    builder: (_) => CollectionManageSheet(collection: collection),
  );
}

/// Rename/delete actions for one collection.
class CollectionManageSheet extends ConsumerWidget {
  const CollectionManageSheet({super.key, required this.collection});

  final Collection collection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.collections_bookmark_outlined),
            title: Text(collection.name),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: Text(context.l10n.commonRename),
            onTap: () {
              AppHaptics.light();
              _rename(context, ref);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: Text(
              context.l10n.commonDelete,
              style: const TextStyle(color: Colors.red),
            ),
            onTap: () {
              AppHaptics.light();
              _confirmDelete(context, ref);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final name = await _promptName(
      context,
      title: context.l10n.libraryRenameCollectionTitle,
      initial: collection.name,
    );
    if (name == null) return; // Cancelled: keep the sheet open.
    if (name.isNotEmpty && name != collection.name) {
      await ref
          .read(collectionRepositoryProvider)
          .renameCollection(collection.id, name);
    }
    if (context.mounted) Navigator.of(context).maybePop();
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.libraryDeleteCollectionConfirmTitle),
        content: Text(
          context.l10n.libraryDeleteCollectionConfirmBody(
            name: collection.name,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () {
              ref
                  .read(collectionRepositoryProvider)
                  .deleteCollection(collection.id);
              Navigator.of(ctx).pop();
              Navigator.of(context).maybePop();
            },
            child: Text(
              context.l10n.commonDelete,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}
