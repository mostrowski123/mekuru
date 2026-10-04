import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/dictionary/data/models/dictionary_catalog.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_catalog_providers.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/shared/widgets/download_status.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/utils/format_bytes.dart';
import 'package:mekuru/shared/utils/haptics.dart';
import 'package:mekuru/shared/widgets/mobile_data_dialog.dart';

/// One downloadable dictionary: what it is, its sizes and license, and a
/// download button that turns into progress, then a check once installed
/// (or an update button when a newer version is out).
class CatalogDictionaryTile extends ConsumerWidget {
  const CatalogDictionaryTile({
    super.key,
    required this.entry,
    this.offerUpdates = true,
  });

  final CatalogDictionary entry;

  /// Off where looking for updates would be a surprise: showing the tile
  /// then checks every installed dictionary over the network.
  final bool offerUpdates;

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
    final hasUpdate =
        offerUpdates &&
        ref.watch(
          dictionaryUpdatesProvider.select(
            (updates) => updates.value?.containsKey(installedId) ?? false,
          ),
        );
    final updateState = hasUpdate
        ? ref.watch(dictionaryUpdateProvider(installedId!))
        : null;

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
            busy: state.isDownloading || (updateState?.isDownloading ?? false),
            installedId: installedId,
            hasUpdate: hasUpdate,
          ),
        ),
        DictionaryDownloadStatus(state: state),
        if (updateState != null) DictionaryDownloadStatus(state: updateState),
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
    required bool hasUpdate,
  }) {
    if (busy) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (installedId != null && hasUpdate) {
      return FilledButton.tonal(
        onPressed: () => startDictionaryDownload(
          context,
          entry,
          ref.read(dictionaryUpdateProvider(installedId).notifier).update,
        ),
        child: Text(context.l10n.dictionaryUpdateButton),
      );
    }
    if (installedId != null) {
      return Icon(
        Icons.check_circle,
        color: Theme.of(context).colorScheme.primary,
        semanticLabel: context.l10n.catalogInstalled,
      );
    }
    return FilledButton.tonal(
      onPressed: () => startDictionaryDownload(
        context,
        entry,
        ref.read(catalogDownloadProvider(entry).notifier).download,
      ),
      child: Text(context.l10n.commonDownload),
    );
  }
}

/// Starts [download] (a dictionary download or update) on Wi-Fi, or off it
/// once the user accepts mobile data; [entry] gives the size when known.
/// Pass the notifier's method itself: the caller can unmount while the
/// dialog is up.
Future<void> startDictionaryDownload(
  BuildContext context,
  CatalogDictionary? entry,
  Future<void> Function() download,
) async {
  AppHaptics.light();
  final l10n = context.l10n;
  final body = entry == null
      ? l10n.dictionaryUpdateMobileDataBody
      : l10n.catalogMobileDataBody(size: _megabytes(entry.downloadMb));
  if (!await okToDownload(context, body)) return;
  unawaited(download());
}

/// Why the last attempt in [state] failed, worded for the user; null when
/// it did not fail.
String? dictionaryDownloadError(
  AppLocalizations l10n,
  CatalogDownloadState state,
) {
  if (state.neededBytes case final bytes?) {
    return l10n.backupFullNotEnoughSpace(size: formatBytes(bytes));
  }
  if (state.error case final error?) {
    return l10n.commonErrorWithDetails(details: error);
  }
  return null;
}

/// Progress and errors of a dictionary download or update, shown under its
/// tile.
class DictionaryDownloadStatus extends StatelessWidget {
  const DictionaryDownloadStatus({super.key, required this.state});

  final CatalogDownloadState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final error = dictionaryDownloadError(l10n, state);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (state.isDownloading)
          DownloadProgress(
            progress: state.progress,
            label: dictionaryDownloadLabel(l10n, state.progress),
          ),
        if (error != null) DownloadErrorText(text: error),
      ],
    );
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
