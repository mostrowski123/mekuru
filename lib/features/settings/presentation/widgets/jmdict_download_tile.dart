import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/dictionary/data/models/dictionary_catalog.dart';
import 'package:mekuru/features/settings/data/services/yomitan_dict_download_service.dart';
import 'package:mekuru/features/settings/presentation/providers/jmdict_providers.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/utils/haptics.dart';
import 'package:mekuru/shared/widgets/download_status.dart';
import 'package:mekuru/shared/widgets/mobile_data_dialog.dart';

// Zip sizes for the mobile-data question, rounded: the JMdict English
// releases were 15.6 and 18.1 MB in October 2026.
const _jmdictSize = '16 MB';
const _jmdictExamplesSize = '18 MB';

/// JMdict English, with or without example sentences: a download button
/// that turns into progress, then into Delete once installed.
class JmdictDownloadTile extends ConsumerStatefulWidget {
  const JmdictDownloadTile({super.key});

  @override
  ConsumerState<JmdictDownloadTile> createState() => _JmdictDownloadTileState();
}

class _JmdictDownloadTileState extends ConsumerState<JmdictDownloadTile> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(jmdictProvider.notifier).checkStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(jmdictProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          title: Text(l10n.downloadsStarterPackJmdict),
          subtitle: Text(
            state.isImported
                ? l10n.downloadsJmdictDownloaded
                : l10n.downloadsJmdictDescription,
          ),
          trailing: _buildTrailing(context, state),
        ),
        if (state.isDownloading)
          DictionaryDownloadProgress(progress: state.progress),
        if (state.error != null) DownloadErrorText(text: state.error!),
        if (state.successMessage != null)
          DownloadSuccessText(text: state.successMessage!),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: DownloadAttributionText(
            linkText: 'JMdict',
            url: edrdgJmdictUrl,
            suffix:
                ' by the Electronic Dictionary Research and '
                'Development Group (EDRDG), licensed under CC BY-SA 4.0.',
          ),
        ),
      ],
    );
  }

  Widget _buildTrailing(BuildContext context, JmdictState state) {
    if (state.isDownloading || state.isDeleting) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (state.isImported) {
      return IconButton(
        icon: Icon(
          Icons.delete_outline,
          color: Theme.of(context).colorScheme.error,
        ),
        tooltip: context.l10n.downloadsDeleteJmdictTooltip,
        onPressed: () => _confirmDelete(context),
      );
    }

    return FilledButton.tonal(
      onPressed: () {
        AppHaptics.light();
        _showVariantPicker(context);
      },
      child: Text(context.l10n.commonDownload),
    );
  }

  void _showVariantPicker(BuildContext context) {
    // Resolved before the sheet opens: the tile can unmount while it's up.
    final container = ProviderScope.containerOf(context, listen: false);
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                ctx.l10n.downloadsChooseJmdictVariant,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.download),
              title: Text(ctx.l10n.downloadsStarterPackJmdict),
              subtitle: Text(ctx.l10n.downloadsJmdictStandardSubtitle),
              onTap: () {
                Navigator.of(ctx).pop();
                askThenDownload(
                  context,
                  _jmdictSize,
                  () => container
                      .read(jmdictProvider.notifier)
                      .download(YomitanDictType.jmdictEnglish),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: Text(ctx.l10n.downloadsJmdictExamplesTitle),
              subtitle: Text(ctx.l10n.downloadsJmdictExamplesSubtitle),
              onTap: () {
                Navigator.of(ctx).pop();
                askThenDownload(
                  context,
                  _jmdictExamplesSize,
                  () => container
                      .read(jmdictProvider.notifier)
                      .download(YomitanDictType.jmdictEnglishWithExamples),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    // Resolved before the dialog opens: the tile can unmount while it's up.
    final container = ProviderScope.containerOf(context, listen: false);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.downloadsDeleteJmdictTitle),
        content: Text(ctx.l10n.downloadsDeleteJmdictBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              container.read(jmdictProvider.notifier).delete();
            },
            child: Text(
              ctx.l10n.commonDelete,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}
