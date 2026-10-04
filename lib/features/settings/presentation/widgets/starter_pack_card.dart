import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/features/dictionary/presentation/screens/dictionary_search_screen.dart';
import 'package:mekuru/features/settings/data/services/yomitan_dict_download_service.dart';
import 'package:mekuru/features/settings/presentation/providers/jmdict_providers.dart';
import 'package:mekuru/features/settings/presentation/providers/jpdb_freq_providers.dart';
import 'package:mekuru/features/settings/presentation/providers/kanjidic_providers.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/utils/app_routes.dart';
import 'package:mekuru/shared/utils/haptics.dart';

// Download sizes for the mobile-data prompt, rounded up: the JMdict English
// release zip was 15.6 MB and the JPDB v2.2 zip 6.0 MB in October 2026.
const _jmdictMb = 16;
const _jpdbMb = 6;

/// Starts whichever recommended dictionaries (JMdict English, JPDB word
/// frequency) aren't installed yet, asking first when Wi-Fi isn't
/// connected. The downloads live in app-wide notifiers, so they keep going
/// when the calling screen goes away.
Future<void> installStarterPack(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final jmdict = container.read(jmdictProvider.notifier);
  final jpdb = container.read(jpdbFreqProvider.notifier);
  // Fresh status first, so nothing installed is downloaded again.
  await Future.wait([jmdict.checkStatus(), jpdb.checkStatus()]);
  final needJmdict = !container.read(jmdictProvider).isImported;
  final needJpdb = !container.read(jpdbFreqProvider).isImported;
  if (!needJmdict && !needJpdb) return;

  if (!await isOnWifi()) {
    if (!context.mounted) return;
    final size = (needJmdict ? _jmdictMb : 0) + (needJpdb ? _jpdbMb : 0);
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.localOcrMobileDownloadTitle),
        content: Text(
          l10n.downloadsStarterPackMobileDataBody(size: '$size MB'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.commonDownload),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
  }

  if (needJmdict) unawaited(jmdict.download(YomitanDictType.jmdictEnglish));
  if (needJpdb) unawaited(jpdb.download());
}

/// One-tap install of the recommended dictionaries: JMdict English plus JPDB
/// word frequency.
class StarterPackCard extends ConsumerStatefulWidget {
  const StarterPackCard({super.key, this.showProgress = true});

  /// Off where each dictionary's own tile already shows its progress and
  /// errors (the Downloads screen).
  final bool showProgress;

  @override
  ConsumerState<StarterPackCard> createState() => _StarterPackCardState();
}

class _StarterPackCardState extends ConsumerState<StarterPackCard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(jmdictProvider.notifier).checkStatus();
      ref.read(jpdbFreqProvider.notifier).checkStatus();
    });
  }

  void _openDictionary() {
    Navigator.of(context).push(
      namedRoute('dictionary_search', (_) => const DictionarySearchScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final jmdict = ref.watch(jmdictProvider);
    final jpdb = ref.watch(jpdbFreqProvider);
    final ready = jmdict.isImported && jpdb.isImported;
    final busy = jmdict.isDownloading || jpdb.isDownloading;
    final hasDictionarySuccess =
        jmdict.successMessage != null ||
        ref.watch(kanjidicProvider.select((s) => s.successMessage != null));
    final inFlight = [
      if (widget.showProgress && jmdict.isDownloading) jmdict.progress,
      if (widget.showProgress && jpdb.isDownloading) jpdb.progress,
    ];
    final error = widget.showProgress ? jmdict.error ?? jpdb.error : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.downloadsRecommendedStarterPackTitle,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            l10n.downloadsRecommendedStarterPackSubtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          _StatusRow(
            label: l10n.downloadsStarterPackJmdict,
            isReady: jmdict.isImported,
          ),
          const SizedBox(height: 8),
          _StatusRow(
            label: l10n.downloadsStarterPackWordFrequency,
            isReady: jpdb.isImported,
          ),
          if (inFlight.isNotEmpty) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: inFlight.reduce((a, b) => a + b) / inFlight.length,
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              error,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: busy
                    ? null
                    : () {
                        AppHaptics.light();
                        ready
                            ? _openDictionary()
                            : unawaited(installStarterPack(context));
                      },
                icon: Icon(ready ? Icons.search : Icons.download_outlined),
                label: Text(
                  ready
                      ? l10n.commonOpenDictionary
                      : l10n.downloadsInstallStarterPack,
                ),
              ),
              if (hasDictionarySuccess && !ready)
                OutlinedButton(
                  onPressed: () {
                    AppHaptics.light();
                    _openDictionary();
                  },
                  child: Text(l10n.commonOpenDictionary),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.isReady});

  final String label;
  final bool isReady;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          isReady ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 18,
          color: isReady
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Text(label, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}
