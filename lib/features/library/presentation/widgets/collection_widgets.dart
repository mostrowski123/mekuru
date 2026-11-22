import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/library/presentation/providers/library_providers.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/utils/haptics.dart';

/// Awaits [write], a change to the library's database. When it fails,
/// [messenger] shows [failure] and telemetry gets [event]. The library draws
/// what the database holds, so a failed write leaves nothing to put back.
/// True when the write went through.
///
/// Take the messenger before the sheet or dialog that asked for the change
/// closes: the write can outlive it.
Future<bool> saveLibraryChange(
  ScaffoldMessengerState messenger,
  Future<void> Function() write, {
  required String failure,
  required String event,
}) async {
  try {
    await write();
    return true;
  } catch (e) {
    // No stack trace, so no Sentry issue: an issue carries the error's whole
    // text, and a rename's SQL parameters hold the new name.
    logFailure(event, e);
    // A sheet's own messenger is gone once the sheet is.
    if (messenger.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(failure)));
    }
    return false;
  }
}

/// [sheet] with a messenger of its own, so its messages show on it rather
/// than on the page underneath. A Scaffold fills the height it is given, so
/// it lies over the sheet instead of holding it, as in showOcrActionSheet.
Widget withOwnMessenger(Widget sheet) => ScaffoldMessenger(
  child: Stack(
    children: [
      sheet,
      const Positioned.fill(
        child: IgnorePointer(
          child: Scaffold(backgroundColor: Colors.transparent),
        ),
      ),
    ],
  ),
);

/// Opens the membership sheet for [book].
Future<void> showCollectionAssignSheet(BuildContext context, Book book) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (_) => withOwnMessenger(CollectionAssignSheet(book: book)),
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
                    onChanged: (checked) async {
                      AppHaptics.light();
                      final next = {...memberIds};
                      if (checked ?? false) {
                        next.add(collection.id);
                      } else {
                        next.remove(collection.id);
                      }
                      final repo = ref.read(collectionRepositoryProvider);
                      await saveLibraryChange(
                        ScaffoldMessenger.of(context),
                        () => repo.setBookCollections(book.id, next),
                        failure: context.l10n.libraryCollectionChangeFailed,
                        event: 'library.collection_change_failed',
                      );
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.add),
                  title: Text(context.l10n.libraryNewCollectionAction),
                  onTap: () async {
                    AppHaptics.light();
                    // Resolved before the prompt: the sheet can unmount
                    // while it's up.
                    final container = ProviderScope.containerOf(
                      context,
                      listen: false,
                    );
                    final name = await _promptName(
                      context,
                      title: context.l10n.libraryNewCollectionAction,
                    );
                    if (name == null || name.isEmpty || !context.mounted) {
                      return;
                    }
                    final messenger = ScaffoldMessenger.of(context);
                    final l10n = context.l10n;
                    final repo = container.read(collectionRepositoryProvider);
                    int? id;
                    await saveLibraryChange(
                      messenger,
                      () async => id = await repo.createCollection(name),
                      failure: l10n.libraryCreateCollectionFailed,
                      event: 'library.collection_create_failed',
                    );
                    final created = id;
                    if (created == null) return;
                    // The new collection also gets this book — that is what
                    // the user came here to do.
                    await saveLibraryChange(
                      messenger,
                      () => repo.setBookCollections(book.id, {
                        ...memberIds,
                        created,
                      }),
                      failure: l10n.libraryCollectionChangeFailed,
                      event: 'library.collection_change_failed',
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

/// Picks collections to add [bookIds] to. Additive only — nothing is ever
/// removed here, unlike the single-book [CollectionAssignSheet] which
/// mirrors membership per toggle.
Future<void> showCollectionPickSheet(BuildContext context, Set<int> bookIds) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (_) => withOwnMessenger(CollectionPickSheet(bookIds: bookIds)),
  );
}

/// Checkbox list of collections with a deferred confirm: nothing is
/// written until the add button commits every chosen collection.
class CollectionPickSheet extends ConsumerStatefulWidget {
  const CollectionPickSheet({super.key, required this.bookIds});

  final Set<int> bookIds;

  @override
  ConsumerState<CollectionPickSheet> createState() =>
      _CollectionPickSheetState();
}

class _CollectionPickSheetState extends ConsumerState<CollectionPickSheet> {
  final Set<int> _chosen = {};

  Future<void> _confirm() async {
    final repo = ref.read(collectionRepositoryProvider);
    final saved = await saveLibraryChange(
      ScaffoldMessenger.of(context),
      () async {
        for (final id in _chosen) {
          await repo.addBooksToCollection(id, widget.bookIds);
        }
      },
      failure: context.l10n.libraryCollectionChangeFailed,
      event: 'library.collection_change_failed',
    );
    // Not saved: the sheet stays up with its message, to try again.
    if (saved && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final collections = ref.watch(collectionsProvider).value ?? const [];
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(title: Text(context.l10n.libraryAddToCollectionAction)),
          const Divider(height: 1),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final collection in collections)
                  CheckboxListTile(
                    value: _chosen.contains(collection.id),
                    title: Text(collection.name),
                    onChanged: (checked) => setState(() {
                      if (checked ?? false) {
                        _chosen.add(collection.id);
                      } else {
                        _chosen.remove(collection.id);
                      }
                    }),
                  ),
                ListTile(
                  leading: const Icon(Icons.add),
                  title: Text(context.l10n.libraryNewCollectionAction),
                  onTap: () async {
                    AppHaptics.light();
                    // Resolved before the prompt: the sheet can unmount
                    // while it's up.
                    final container = ProviderScope.containerOf(
                      context,
                      listen: false,
                    );
                    final name = await _promptName(
                      context,
                      title: context.l10n.libraryNewCollectionAction,
                    );
                    if (name == null || name.isEmpty || !context.mounted) {
                      return;
                    }
                    final repo = container.read(collectionRepositoryProvider);
                    int? id;
                    await saveLibraryChange(
                      ScaffoldMessenger.of(context),
                      () async => id = await repo.createCollection(name),
                      failure: context.l10n.libraryCreateCollectionFailed,
                      event: 'library.collection_create_failed',
                    );
                    final created = id;
                    if (created != null && mounted) {
                      setState(() => _chosen.add(created));
                    }
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _chosen.isEmpty ? null : _confirm,
                child: Text(context.l10n.commonAdd),
              ),
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

/// "Add to favorites" / "Remove from favorites" in the long-press sheet of
/// a book or a folder.
class FavoriteToggleTile extends StatelessWidget {
  const FavoriteToggleTile({
    super.key,
    required this.isFavorite,
    required this.onToggle,
  });

  final bool isFavorite;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(isFavorite ? Icons.star : Icons.star_outline),
      title: Text(
        isFavorite
            ? context.l10n.libraryRemoveFromFavorites
            : context.l10n.libraryAddToFavorites,
      ),
      onTap: () {
        AppHaptics.light();
        onToggle();
      },
    );
  }
}

/// Favorite/rename/delete actions for one collection. Each closes the sheet,
/// so a failure shows on the page underneath.
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
          FavoriteToggleTile(
            isFavorite: collection.isFavorite,
            onToggle: () {
              unawaited(
                saveLibraryChange(
                  ScaffoldMessenger.of(context),
                  () => ref
                      .read(collectionRepositoryProvider)
                      .setFavorite(collection.id, !collection.isFavorite),
                  failure: context.l10n.libraryFavoriteChangeFailed,
                  event: 'library.favorite_change_failed',
                ),
              );
              unawaited(Navigator.of(context).maybePop());
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: Text(context.l10n.commonRename),
            onTap: () async {
              AppHaptics.light();
              await _rename(context);
            },
          ),
          ListTile(
            iconColor: Theme.of(context).colorScheme.error,
            textColor: Theme.of(context).colorScheme.error,
            leading: const Icon(Icons.delete_outline),
            title: Text(context.l10n.commonDelete),
            onTap: () async {
              AppHaptics.light();
              await _confirmDelete(context);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context) async {
    // Resolved before the prompt: the sheet can unmount while it's up.
    final container = ProviderScope.containerOf(context, listen: false);
    final name = await _promptName(
      context,
      title: context.l10n.libraryRenameCollectionTitle,
      initial: collection.name,
    );
    // Cancelled: keep the sheet open.
    if (name == null || !context.mounted) return;
    if (name.isNotEmpty && name != collection.name) {
      final repo = container.read(collectionRepositoryProvider);
      unawaited(
        saveLibraryChange(
          ScaffoldMessenger.of(context),
          () => repo.renameCollection(collection.id, name),
          failure: context.l10n.libraryRenameCollectionFailed,
          event: 'library.collection_rename_failed',
        ),
      );
    }
    unawaited(Navigator.of(context).maybePop());
  }

  Future<void> _confirmDelete(BuildContext context) {
    // Resolved before the dialog opens: the sheet can unmount while it's up.
    final container = ProviderScope.containerOf(context, listen: false);
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.libraryDeleteCollectionConfirmTitle),
        content: Text(
          ctx.l10n.libraryDeleteCollectionConfirmBody(name: collection.name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () {
              unawaited(
                saveLibraryChange(
                  ScaffoldMessenger.of(ctx),
                  () => container
                      .read(collectionRepositoryProvider)
                      .deleteCollection(collection.id),
                  failure: ctx.l10n.libraryDeleteCollectionFailed,
                  event: 'library.collection_delete_failed',
                ),
              );
              Navigator.of(ctx).pop();
              if (context.mounted) unawaited(Navigator.of(context).maybePop());
            },
            child: Text(
              ctx.l10n.commonDelete,
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }
}
