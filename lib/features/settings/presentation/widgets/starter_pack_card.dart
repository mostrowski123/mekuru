import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/features/dictionary/data/models/dictionary_catalog.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_download_service.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_catalog_providers.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/features/dictionary/presentation/screens/dictionary_search_screen.dart';
import 'package:mekuru/features/settings/data/services/yomitan_dict_download_service.dart';
import 'package:mekuru/features/settings/presentation/providers/jmdict_providers.dart';
import 'package:mekuru/features/settings/presentation/providers/jpdb_freq_providers.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/utils/app_routes.dart';
import 'package:mekuru/shared/utils/haptics.dart';
import 'package:mekuru/shared/widgets/download_status.dart';
import 'package:mekuru/shared/widgets/mobile_data_dialog.dart';

// Download size for the mobile-data prompt, rounded up: the JPDB v2.2 zip
// was 6.0 MB in October 2026.
const _jpdbMb = 6;

/// The installed dictionaries that stand for the starter pack's: Jitendex,
/// and JMdict English, which the pack installed before it offered Jitendex.
({bool jitendex, bool jmdict}) _starterDictionaries(
  Iterable<DictionaryMeta> installed,
) => (
  jitendex: CatalogDictionary.jitendex.isInstalledIn(installed),
  jmdict: YomitanDictDownloadService.isImportedIn(
    YomitanDictType.jmdictEnglish,
    installed,
  ),
);

/// Starts whichever recommended dictionaries (Jitendex, JPDB word
/// frequency) aren't installed yet, asking first when Wi-Fi isn't
/// connected. JMdict English, installed or on its way, stands in for
/// Jitendex. The downloads live in app-wide notifiers, so they keep going
/// when the calling screen goes away.
Future<void> installStarterPack(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final jpdb = container.read(jpdbFreqProvider.notifier);
  // Fresh status first, so nothing installed is downloaded again.
  final (_, dictionaries) = await (
    jpdb.checkStatus(),
    container.read(dictionariesProvider.future),
  ).wait;
  final installed = _starterDictionaries(dictionaries);
  final needDictionary =
      !installed.jitendex &&
      !installed.jmdict &&
      !container.read(jmdictProvider).isDownloading;
  final needJpdb = !container.read(jpdbFreqProvider).isImported;
  if (!needDictionary && !needJpdb) return;

  // Only the mobile-data question needs the caller still on screen.
  if (!await isOnWifi()) {
    if (!context.mounted) return;
    final mb =
        (needDictionary ? CatalogDictionary.jitendex.downloadMb.ceil() : 0) +
        (needJpdb ? _jpdbMb : 0);
    final size = '$mb MB';
    final confirmed = await confirmMobileData(
      context,
      size: size,
      body: context.l10n.downloadsStarterPackMobileDataBody(size: size),
    );
    if (!confirmed) return;
  }

  if (needDictionary) {
    unawaited(
      container
          .read(catalogDownloadProvider(CatalogDictionary.jitendex).notifier)
          .download(),
    );
  }
  if (needJpdb) unawaited(jpdb.download());
}

/// One-tap install of the recommended dictionaries: Jitendex plus JPDB word
/// frequency.
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
    final installed = ref.watch(
      dictionariesProvider.select(
        (dictionaries) => _starterDictionaries(dictionaries.value ?? const []),
      ),
    );
    final jitendex = ref.watch(
      catalogDownloadProvider(CatalogDictionary.jitendex),
    );
    final jpdb = ref.watch(jpdbFreqProvider);
    final hasDictionary = installed.jitendex || installed.jmdict;
    final ready = hasDictionary && jpdb.isImported;
    final busy = jitendex.isDownloading || jpdb.isDownloading;
    final inFlight = [
      if (jitendex.isDownloading) jitendex.progress,
      if (jpdb.isDownloading) jpdb.progress,
    ];
    // The import's finish reports nothing, so the bar moves on its own.
    final finishing = inFlight.every(
      (p) => p >= DictionaryDownloadService.finishingProgress,
    );
    final error = widget.showProgress
        ? dictionaryDownloadError(l10n, jitendex.failure) ?? jpdb.error
        : null;

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
            label: installed.jmdict && !installed.jitendex
                ? l10n.downloadsStarterPackJmdict
                : CatalogDictionary.jitendex.displayName,
            isReady: hasDictionary,
          ),
          const SizedBox(height: 8),
          _StatusRow(
            label: l10n.downloadsStarterPackWordFrequency,
            isReady: jpdb.isImported,
          ),
          if (widget.showProgress && inFlight.isNotEmpty) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: finishing
                  ? null
                  : inFlight.reduce((a, b) => a + b) / inFlight.length,
            ),
            if (finishing) ...[
              const SizedBox(height: 4),
              Text(
                l10n.dictionaryImportFinishing,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
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
              if (hasDictionary && !ready)
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
