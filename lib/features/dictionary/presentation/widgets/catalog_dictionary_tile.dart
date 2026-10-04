import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/dictionary/data/models/dictionary_catalog.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_catalog_providers.dart';
import 'package:mekuru/shared/widgets/download_status.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/utils/format_bytes.dart';
import 'package:mekuru/shared/utils/haptics.dart';
import 'package:mekuru/shared/widgets/mobile_data_dialog.dart';

/// One downloadable dictionary: what it is, its sizes and license, and a
/// download button that turns into progress, then a check once installed.
class CatalogDictionaryTile extends ConsumerWidget {
  const CatalogDictionaryTile({super.key, required this.entry});

  final CatalogDictionary entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(catalogDownloadProvider(entry));
    final installed = ref.watch(
      installedCatalogDictionariesProvider.select((s) => s.contains(entry)),
    );
    final neededBytes = state.neededBytes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          title: Text(entry.displayName),
          subtitle: Text(
            '${_catalogDescription(l10n, entry)}\n'
            '${l10n.catalogSizes(download: _megabytes(entry.downloadMb), installed: _megabytes(entry.installedMb))}',
          ),
          isThreeLine: true,
          trailing: _trailing(context, ref, state, installed),
        ),
        if (state.isDownloading)
          DownloadProgress(
            progress: state.progress,
            label: dictionaryDownloadLabel(l10n, state.progress),
          ),
        if (neededBytes != null)
          DownloadErrorText(
            text: l10n.backupFullNotEnoughSpace(size: formatBytes(neededBytes)),
          ),
        if (state.error != null)
          DownloadErrorText(
            text: l10n.commonErrorWithDetails(details: state.error!),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: DownloadAttributionText(
            linkText: 'CC BY-SA 4.0',
            url: entry.sourceUrl,
          ),
        ),
      ],
    );
  }

  Widget _trailing(
    BuildContext context,
    WidgetRef ref,
    CatalogDownloadState state,
    bool installed,
  ) {
    if (state.isDownloading) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (installed) {
      return Icon(
        Icons.check_circle,
        color: Theme.of(context).colorScheme.primary,
        semanticLabel: context.l10n.catalogInstalled,
      );
    }
    return FilledButton.tonal(
      onPressed: () => _download(context, ref),
      child: Text(context.l10n.commonDownload),
    );
  }

  Future<void> _download(BuildContext context, WidgetRef ref) async {
    AppHaptics.light();
    // Read before any await: the tile can unmount while a dialog is up.
    final notifier = ref.read(catalogDownloadProvider(entry).notifier);
    final body = context.l10n.catalogMobileDataBody(
      size: _megabytes(entry.downloadMb),
    );
    if (!await okToDownload(context, body)) return;
    unawaited(notifier.download());
  }
}

String _megabytes(double mb) =>
    mb >= 10 ? '${mb.round()} MB' : '${mb.toStringAsFixed(1)} MB';

/// The short description shown under a catalog dictionary's name.
String _catalogDescription(AppLocalizations l10n, CatalogDictionary entry) =>
    switch (entry) {
      CatalogDictionary.jitendex => l10n.catalogJitendexDescription,
      CatalogDictionary.wiktionaryEnglish =>
        l10n.catalogWiktionaryEnglishDescription,
      CatalogDictionary.wiktionaryJapanese =>
        l10n.catalogWiktionaryJapaneseDescription,
      CatalogDictionary.wiktionaryChinese =>
        l10n.catalogWiktionaryChineseDescription,
      CatalogDictionary.jmnedict => l10n.catalogJmnedictDescription,
      CatalogDictionary.jmdictSpanish ||
      CatalogDictionary.jmdictGerman ||
      CatalogDictionary.jmdictFrench ||
      CatalogDictionary.jmdictRussian ||
      CatalogDictionary.jmdictDutch ||
      CatalogDictionary.jmdictHungarian ||
      CatalogDictionary.jmdictSwedish ||
      CatalogDictionary.jmdictSlovenian =>
        l10n.catalogJmdictLanguageDescription,
      CatalogDictionary.kanjidicSpanish ||
      CatalogDictionary.kanjidicFrench ||
      CatalogDictionary.kanjidicPortuguese =>
        l10n.catalogKanjidicLanguageDescription,
    };
