// ignore_for_file: discarded_futures
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/downloads/download_tile_state.dart';

/// The row of a download that [provider] installs and deletes: a spinner
/// while it works, then Delete (asking first, in [deleteTitle] and
/// [deleteBody]) once installed, else Download, which calls [onDownload]
/// with the row's context (null: the button is off). Its progress and
/// outcome go below it, where its screen puts them.
class DownloadTile extends ConsumerWidget {
  const DownloadTile({
    super.key,
    required this.provider,
    this.icon,
    required this.title,
    required this.subtitle,
    this.enabled = true,
    this.onTap,
    required this.onDownload,
    required this.deleteTooltip,
    required this.deleteTitle,
    required this.deleteBody,
  });

  final NotifierProvider<DownloadTileNotifier, DownloadTileState> provider;
  final IconData? icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback? onTap;
  final void Function(BuildContext context)? onDownload;
  final String deleteTooltip;
  final String deleteTitle;
  final String deleteBody;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(provider);
    final theme = Theme.of(context);
    return ListTile(
      enabled: enabled,
      leading: icon == null
          ? null
          : Icon(icon, color: theme.colorScheme.primary),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: state.isDownloading || state.isDeleting
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : state.isInstalled
          ? IconButton(
              icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
              tooltip: deleteTooltip,
              onPressed: () => _confirmDelete(context),
            )
          : FilledButton.tonal(
              onPressed: switch (onDownload) {
                final download? => () => download(context),
                null => null,
              },
              child: Text(context.l10n.commonDownload),
            ),
      onTap: onTap,
    );
  }

  void _confirmDelete(BuildContext context) {
    // Resolved before the dialog opens: the tile can unmount while it's up.
    final container = ProviderScope.containerOf(context, listen: false);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(deleteTitle),
        content: Text(deleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              container.read(provider.notifier).delete();
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
