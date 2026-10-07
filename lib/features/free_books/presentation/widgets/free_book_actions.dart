import 'package:flutter/material.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/utils/app_routes.dart';
import 'package:mekuru/shared/utils/haptics.dart';
import 'package:url_launcher/url_launcher.dart';

/// A free book's details-sheet buttons: "View on" its site, and Download,
/// or Read once the library has [copy]. Under them, why the last download
/// failed.
class FreeBookActions extends StatelessWidget {
  const FreeBookActions({
    super.key,
    required this.viewLabel,
    required this.viewUrl,
    required this.copy,
    required this.progress,
    required this.error,
    required this.onDownload,
  });

  final String viewLabel;
  final Uri viewUrl;
  final Book? copy;

  /// Download progress 0..1 (0 = indeterminate), or null when idle.
  final double? progress;

  /// Why the last download failed, or null. The sheet covers the snack bar
  /// that also says it.
  final String? error;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final copy = this.copy;
    final progress = this.progress;
    final error = this.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.open_in_new),
                label: Text(viewLabel),
                onPressed: () =>
                    launchUrl(viewUrl, mode: LaunchMode.externalApplication),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: copy != null
                  ? FilledButton.icon(
                      icon: const Icon(Icons.menu_book),
                      label: Text(l10n.freeBooksRead),
                      onPressed: () {
                        final navigator = Navigator.of(context);
                        navigator.pop();
                        navigator.push(bookReaderRoute(copy));
                      },
                    )
                  : FilledButton.icon(
                      icon: progress == null
                          ? const Icon(Icons.download)
                          : SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                value: progress > 0 ? progress : null,
                                strokeWidth: 2,
                              ),
                            ),
                      label: Text(
                        progress == null
                            ? l10n.commonDownload
                            : l10n.freeBooksDownloading,
                      ),
                      onPressed: progress != null
                          ? null
                          : () {
                              AppHaptics.medium();
                              onDownload();
                            },
                    ),
            ),
          ],
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}

/// What a Free books tab shows when its search and filters match nothing.
class FreeBooksNoResults extends StatelessWidget {
  const FreeBooksNoResults({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(context.l10n.freeBooksNoResults, textAlign: TextAlign.center),
    ),
  );
}
