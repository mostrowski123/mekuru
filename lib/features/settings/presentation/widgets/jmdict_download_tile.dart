// ignore_for_file: discarded_futures
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/dictionary/data/models/dictionary_catalog.dart';
import 'package:mekuru/features/settings/data/services/yomitan_dict_download_service.dart';
import 'package:mekuru/features/settings/presentation/providers/fixed_dictionary_providers.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/utils/haptics.dart';
import 'package:mekuru/shared/widgets/download_status.dart';
import 'package:mekuru/shared/widgets/download_tile.dart';
import 'package:mekuru/shared/widgets/mobile_data_dialog.dart';

// Zip sizes for the mobile-data question, rounded: the JMdict English
// releases were 15.6 and 18.1 MB in October 2026.
const _jmdictSize = '16 MB';
const _jmdictExamplesSize = '18 MB';

final _jmdict = fixedDictionaryProvider(FixedDictionary.jmdict);

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
      ref.read(_jmdict.notifier).checkStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(_jmdict);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DownloadTile(
          provider: _jmdict,
          title: l10n.downloadsStarterPackJmdict,
          subtitle: state.isInstalled
              ? l10n.downloadsJmdictDownloaded
              : l10n.downloadsJmdictDescription,
          onDownload: (context) {
            AppHaptics.light();
            _showVariantPicker(context);
          },
          deleteTooltip: l10n.downloadsDeleteJmdictTooltip,
          deleteTitle: l10n.downloadsDeleteJmdictTitle,
          deleteBody: l10n.downloadsDeleteJmdictBody,
        ),
        if (state.isDownloading)
          DictionaryDownloadProgress(progress: state.progress),
        if (state.outcome case final outcome?) DownloadOutcomeText(outcome),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: DownloadAttributionText(
            linkText: 'JMdict',
            url: edrdgJmdictUrl,
            suffix: context.l10n.downloadsEdrdgAttributionSuffix,
          ),
        ),
      ],
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
                _download(
                  container,
                  YomitanDictType.jmdictEnglish,
                  _jmdictSize,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: Text(ctx.l10n.downloadsJmdictExamplesTitle),
              subtitle: Text(ctx.l10n.downloadsJmdictExamplesSubtitle),
              onTap: () {
                Navigator.of(ctx).pop();
                _download(
                  container,
                  YomitanDictType.jmdictEnglishWithExamples,
                  _jmdictExamplesSize,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// The mobile-data question for [variant], a zip of [size], then its
  /// download. [container] is resolved before: the tile can unmount while
  /// the question is up.
  Future<void> _download(
    ProviderContainer container,
    YomitanDictType variant,
    String size,
  ) => askThenDownload(
    context,
    size,
    (network) => container.read(_jmdict.notifier).download(network, variant),
  );
}
