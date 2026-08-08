import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/library/presentation/providers/library_providers.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/utils/haptics.dart';

/// Horizontal chip row filtering the library grid by collection.
/// Renders nothing while no collections exist.
class CollectionFilterRow extends ConsumerWidget {
  const CollectionFilterRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collections = ref.watch(collectionsProvider).value ?? const [];
    if (collections.isEmpty) return const SizedBox.shrink();

    final selected = ref.watch(selectedCollectionProvider);
    final notifier = ref.read(selectedCollectionProvider.notifier);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          ChoiceChip(
            label: Text(context.l10n.libraryCollectionsAll),
            selected: selected == null,
            onSelected: (_) {
              AppHaptics.light();
              notifier.select(null);
            },
          ),
          for (final collection in collections)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: GestureDetector(
                onLongPress: () {
                  AppHaptics.medium();
                  showCollectionManageSheet(context, collection);
                },
                child: ChoiceChip(
                  label: Text(collection.name),
                  selected: selected == collection.id,
                  onSelected: (_) {
                    AppHaptics.light();
                    notifier.select(
                      selected == collection.id ? null : collection.id,
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

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
                      checked == true
                          ? next.add(collection.id)
                          : next.remove(collection.id);
                      ref
                          .read(collectionRepositoryProvider)
                          .setBookCollections(book.id, next);
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.add),
                  title: Text(context.l10n.libraryNewCollectionAction),
                  onTap: () {
                    AppHaptics.light();
                    _createCollection(
                      context,
                      ref,
                      assignTo: (book, memberIds),
                    );
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

/// Name dialog → create; when [assignTo] is given, the new collection is
/// also assigned to that book on top of its current memberships.
Future<void> _createCollection(
  BuildContext context,
  WidgetRef ref, {
  (Book, Set<int>)? assignTo,
}) {
  final controller = TextEditingController();
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(context.l10n.libraryNewCollectionAction),
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
          onPressed: () async {
            final name = controller.text.trim();
            Navigator.of(ctx).pop();
            if (name.isEmpty) return;
            final repo = ref.read(collectionRepositoryProvider);
            final id = await repo.createCollection(name);
            if (assignTo != null) {
              final (book, memberIds) = assignTo;
              await repo.setBookCollections(book.id, {...memberIds, id});
            }
          },
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
              _showRenameDialog(context, ref);
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

  void _showRenameDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController(text: collection.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.libraryRenameCollectionTitle),
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
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty && name != collection.name) {
                ref
                    .read(collectionRepositoryProvider)
                    .renameCollection(collection.id, name);
              }
              Navigator.of(ctx).pop();
              Navigator.of(context).maybePop();
            },
            child: Text(context.l10n.commonSave),
          ),
        ],
      ),
    );
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
              final notifier = ref.read(selectedCollectionProvider.notifier);
              if (ref.read(selectedCollectionProvider) == collection.id) {
                notifier.select(null);
              }
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
