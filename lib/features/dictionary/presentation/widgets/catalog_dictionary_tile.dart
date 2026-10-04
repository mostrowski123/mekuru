import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/dictionary/data/models/dictionary_catalog.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_catalog_providers.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/features/dictionary/presentation/widgets/delete_dictionary_dialog.dart';
import 'package:mekuru/shared/widgets/download_status.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/utils/haptics.dart';
import 'package:mekuru/shared/widgets/mobile_data_dialog.dart';

/// One downloadable dictionary: what it is, its sizes and license, and a
/// download button that turns into progress, then into Delete once
/// installed (a newer version comes from deleting and downloading again).
class CatalogDictionaryTile extends ConsumerWidget {
  const CatalogDictionaryTile({super.key, required this.entry});

  final CatalogDictionary entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(catalogDownloadProvider(entry));
    // Installed at any revision, also by hand. Catalog dictionaries are
    // never hidden, so the visible list has them all.
    final installedId = ref.watch(
      dictionariesProvider.select(
        (list) => list.value
            ?.where((d) => entry.matchesTitle(d.name))
            .firstOrNull
            ?.id,
      ),
    );

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
          trailing: _trailing(
            context,
            ref,
            busy: state.isDownloading || state.isDeleting,
            installedId: installedId,
          ),
        ),
        if (state.isDownloading)
          DownloadProgress(
            progress: state.progress,
            label: dictionaryDownloadLabel(l10n, state.progress),
          ),
        if (dictionaryDownloadError(l10n, state.failure) case final error?)
          DownloadErrorText(text: error),
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
    WidgetRef ref, {
    required bool busy,
    required int? installedId,
  }) {
    if (busy) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (installedId != null) {
      return IconButton(
        icon: Icon(
          Icons.delete_outline,
          color: Theme.of(context).colorScheme.error,
        ),
        tooltip: context.l10n.dictionaryManagerDeleteTitle,
        onPressed: () => _delete(context, ref, installedId),
      );
    }
    return FilledButton.tonal(
      onPressed: () => _download(context, ref),
      child: Text(context.l10n.commonDownload),
    );
  }

  /// On Wi-Fi, or off it once the user accepts mobile data.
  Future<void> _download(BuildContext context, WidgetRef ref) async {
    AppHaptics.light();
    // Read now: the tile can unmount while the dialog is up.
    final notifier = ref.read(catalogDownloadProvider(entry).notifier);
    final body = context.l10n.catalogMobileDataBody(
      size: _megabytes(entry.downloadMb),
    );
    if (await okToDownload(context, body)) unawaited(notifier.download());
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, int id) async {
    // Read now: the tile can unmount while the dialog is up.
    final notifier = ref.read(catalogDownloadProvider(entry).notifier);
    if (await confirmDeleteDictionary(context, entry.displayName)) {
      unawaited(notifier.delete(id));
    }
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
