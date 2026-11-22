// ignore_for_file: discarded_futures
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/reader/data/services/gemma_translation.dart';
import 'package:mekuru/features/reader/data/services/sentence_translation.dart';
import 'package:mekuru/features/reader/presentation/providers/gemma_download_provider.dart';
import 'package:mekuru/features/reader/presentation/widgets/translation_memory_warning.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/dictionary/data/models/dictionary_catalog.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/features/dictionary/presentation/screens/dictionary_catalog_screen.dart';
import 'package:mekuru/features/dictionary/presentation/screens/dictionary_manager_screen.dart';
import 'package:mekuru/features/dictionary/presentation/widgets/catalog_dictionary_tile.dart';
import 'package:mekuru/features/manga/presentation/providers/local_ocr_providers.dart';
import 'package:mekuru/features/manga/presentation/widgets/local_ocr_widgets.dart';
import 'package:mekuru/features/manga/presentation/widgets/manga_ocr_ios_download_tile.dart';
import 'package:mekuru/features/settings/data/services/jpdb_freq_download_service.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/features/settings/presentation/providers/fixed_dictionary_providers.dart';
import 'package:mekuru/features/settings/presentation/providers/enhanced_furigana_dict_providers.dart';
import 'package:mekuru/features/settings/presentation/providers/kanjivg_providers.dart';
import 'package:mekuru/shared/downloads/download.dart';
import 'package:mekuru/shared/widgets/download_status.dart';
import 'package:mekuru/shared/widgets/download_tile.dart';
import 'package:mekuru/shared/widgets/mobile_data_dialog.dart';
import 'package:mekuru/features/settings/presentation/widgets/starter_pack_card.dart';
import 'package:mekuru/features/word_audio/presentation/widgets/word_audio_download_tile.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/utils/app_routes.dart';
import 'package:mekuru/shared/utils/haptics.dart';
import 'package:mekuru/shared/widgets/settings/settings_rows.dart';

final _jpdb = fixedDictionaryProvider(FixedDictionary.jpdb);
final _kanjidic = fixedDictionaryProvider(FixedDictionary.kanjidic);

/// Screen listing all downloadable assets (dictionaries, kanji data, etc.).
class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(kanjiVgProvider.notifier).checkStatus();
      ref.read(_jpdb.notifier).checkStatus();
      ref.read(_kanjidic.notifier).checkStatus();
      ref.read(enhancedFuriganaDictProvider.notifier).checkStatus();
      ref
          .read(enhancedFuriganaDictEnabledProvider.notifier)
          .loadPersistedSettings();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final kanjiVgState = ref.watch(kanjiVgProvider);
    final jpdbFreqState = ref.watch(_jpdb);
    final kanjidicState = ref.watch(_kanjidic);
    final enhancedFuriganaState = ref.watch(enhancedFuriganaDictProvider);
    final lowRamMode = ref.watch(lowRamModeProvider);
    final theme = Theme.of(context);
    // Installed but switched off in the dictionary list: it ranks nothing,
    // and a tap goes where it is switched on.
    final jpdbOff =
        jpdbFreqState.isInstalled &&
        ref.watch(
          dictionariesProvider.select(
            (d) => JpdbFreqDownloadService.isSwitchedOffIn(d.value ?? []),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.downloadsTitle)),
      body: ListView(
        children: [
          // ── Dictionaries ──
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: StarterPackCard(showProgress: false),
          ),
          SettingsSectionHeader(title: l10n.downloadsSectionDictionaries),
          const CatalogDictionaryTile(entry: CatalogDictionary.jitendex),

          // KANJIDIC
          DownloadTile(
            provider: _kanjidic,
            icon: Icons.font_download_outlined,
            title: l10n.downloadsKanjidicTitle,
            subtitle: kanjidicState.isInstalled
                ? l10n.downloadsKanjidicDownloaded
                : l10n.downloadsKanjidicDescription,
            onDownload: (context) => askThenDownload(
              context,
              _kanjidicSize,
              ref.read(_kanjidic.notifier).download,
            ),
            deleteTooltip: l10n.downloadsDeleteKanjidicTooltip,
            deleteTitle: l10n.downloadsDeleteKanjidicTitle,
            deleteBody: l10n.downloadsDeleteKanjidicBody,
          ),
          if (kanjidicState.isDownloading)
            DictionaryDownloadProgress(progress: kanjidicState.progress),
          if (kanjidicState.outcome case final outcome?)
            DownloadOutcomeText(outcome, kind: DownloadKind.fixedDictionary),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: DownloadAttributionText(
              linkText: 'KANJIDIC',
              url: edrdgKanjidicUrl,
              suffix: l10n.downloadsEdrdgAttributionSuffix,
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: Icon(
              Icons.library_add_outlined,
              color: theme.colorScheme.primary,
            ),
            title: Text(l10n.catalogTitle),
            subtitle: Text(l10n.catalogEntrySubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              namedRoute(
                'dictionary_catalog',
                (_) => const DictionaryCatalogScreen(),
              ),
            ),
          ),
          const Divider(),

          // ── Assets ──
          SettingsSectionHeader(title: l10n.downloadsSectionAssets),

          // KanjiVG
          DownloadTile(
            provider: kanjiVgProvider,
            icon: Icons.brush_outlined,
            title: l10n.downloadsKanjiStrokeOrderTitle,
            subtitle: kanjiVgState.isInstalled
                ? l10n.downloadsKanjiStrokeOrderDownloaded(
                    count: kanjiVgState.fileCount,
                  )
                : l10n.downloadsKanjiStrokeOrderDescription,
            onDownload: (context) => askThenDownload(
              context,
              _kanjiVgSize,
              ref.read(kanjiVgProvider.notifier).download,
              body: (size) => context.l10n
                  .downloadsKanjiStrokeOrderMobileDataBody(size: size),
            ),
            deleteTooltip: l10n.downloadsDeleteKanjiDataTooltip,
            deleteTitle: l10n.downloadsDeleteKanjiDataTitle,
            deleteBody: l10n.downloadsDeleteKanjiDataBody,
          ),
          if (kanjiVgState.isDownloading)
            DownloadProgress(
              progress: kanjiVgState.progress,
              label: kanjiVgState.progress < 0.9
                  ? l10n.downloadsDownloadingPercent(
                      percent: (kanjiVgState.progress * 100).toInt(),
                    )
                  : l10n.downloadsExtractingFiles,
            ),
          if (kanjiVgState.outcome case final outcome?)
            DownloadOutcomeText(outcome, kind: DownloadKind.kanjiVg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: DownloadAttributionText(
              prefix: l10n.downloadsKanjiVgAttributionPrefix,
              linkText: 'KanjiVG',
              url: 'https://kanjivg.tagaini.net/',
              suffix: l10n.downloadsKanjiVgAttributionSuffix,
            ),
          ),
          const SizedBox(height: 8),

          // JPDB Frequency
          DownloadTile(
            provider: _jpdb,
            icon: Icons.bar_chart_outlined,
            title: l10n.downloadsStarterPackWordFrequency,
            subtitle: jpdbOff
                ? l10n.downloadsWordFrequencySwitchedOff
                : jpdbFreqState.isInstalled
                ? l10n.downloadsWordFrequencyDownloaded
                : l10n.downloadsWordFrequencyDescription,
            onTap: jpdbOff
                ? () => Navigator.of(context).push(
                    namedRoute(
                      'dictionary_manager',
                      (_) => const DictionaryManagerScreen(),
                    ),
                  )
                : null,
            onDownload: (context) => askThenDownload(
              context,
              _jpdbSize,
              ref.read(_jpdb.notifier).download,
            ),
            deleteTooltip: l10n.downloadsDeleteFrequencyDataTooltip,
            deleteTitle: l10n.downloadsDeleteFrequencyDataTitle,
            deleteBody: l10n.downloadsDeleteFrequencyDataBody,
          ),
          if (jpdbFreqState.isDownloading)
            DictionaryDownloadProgress(progress: jpdbFreqState.progress),
          if (jpdbFreqState.outcome case final outcome?)
            DownloadOutcomeText(outcome, kind: DownloadKind.fixedDictionary),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              l10n.downloadsJpdbAttribution,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Enhanced Furigana Dictionary (UniDic-lite, optional download).
          // Low RAM mode never loads it (MeCab stays on IPADIC). Its files
          // can still be deleted.
          DownloadTile(
            provider: enhancedFuriganaDictProvider,
            icon: Icons.spellcheck_outlined,
            title: l10n.downloadsEnhancedFuriganaTitle,
            subtitle: lowRamMode
                ? l10n.lowRamModeOffHere
                : enhancedFuriganaState.isInstalled
                ? l10n.downloadsEnhancedFuriganaInstalled
                : l10n.downloadsEnhancedFuriganaDescription,
            enabled: !lowRamMode,
            // No confirmation of its own: the subtitle already gives both
            // sizes.
            onDownload: lowRamMode
                ? null
                : (context) => askThenDownload(
                    context,
                    _enhancedFuriganaSize,
                    ref.read(enhancedFuriganaDictProvider.notifier).download,
                  ),
            deleteTooltip: l10n.downloadsEnhancedFuriganaRemoveTooltip,
            deleteTitle: l10n.downloadsEnhancedFuriganaConfirmRemoveTitle,
            deleteBody: l10n.downloadsEnhancedFuriganaConfirmRemoveBody,
          ),
          // Kill-switch: lets the user disable the enhanced dictionary
          // without deleting the ~250 MB download. Useful as a recovery step
          // if word tapping ever stops working on a particular device.
          if (enhancedFuriganaState.isInstalled && !lowRamMode)
            SwitchListTile(
              secondary: Icon(
                Icons.tune_outlined,
                color: theme.colorScheme.primary,
              ),
              title: Text(l10n.downloadsEnhancedFuriganaUseTitle),
              subtitle: Text(l10n.downloadsEnhancedFuriganaUseSubtitle),
              value: ref.watch(enhancedFuriganaDictEnabledProvider),
              onChanged: (value) {
                AppHaptics.light();
                ref
                    .read(enhancedFuriganaDictEnabledProvider.notifier)
                    .setEnabled(value);
              },
            ),
          if (enhancedFuriganaState.isDownloading)
            DownloadProgress(
              progress: enhancedFuriganaState.progress,
              label: enhancedFuriganaState.progress < 0.85
                  ? l10n.downloadsEnhancedFuriganaDownloadingPercent(
                      percent: (enhancedFuriganaState.progress / 0.85 * 100)
                          .toInt(),
                    )
                  : l10n.downloadsEnhancedFuriganaExtracting,
            ),
          if (enhancedFuriganaState.outcome case final outcome?)
            DownloadOutcomeText(
              outcome,
              kind: DownloadKind.uniDic,
              // Low RAM mode never loads it (the download can outlast
              // turning the mode on).
              downloaded: lowRamMode
                  ? l10n.downloadsEnhancedFuriganaInstalledLowRam
                  : l10n.downloadsEnhancedFuriganaInstalledRestart,
              deleted: l10n.downloadsEnhancedFuriganaRemoved,
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: DownloadAttributionText(
              prefix: l10n.downloadsUniDicAttributionPrefix,
              linkText: 'UniDic',
              url: 'https://clrd.ninjal.ac.jp/unidic/',
              suffix: l10n.downloadsUniDicAttributionSuffix,
            ),
          ),
          const SizedBox(height: 8),
          const WordAudioDownloadTile(),
          const WordAudioPackTile(),
          // iOS finds text with Apple Vision and needs only the manga-ocr
          // files; Android's pack and its download run in the native service.
          if (defaultTargetPlatform == TargetPlatform.iOS)
            const MangaOcrIosDownloadTile()
          else if (!lowRamMode) ...[
            // iOS language packs belong to the system (Settings > Apps >
            // Translate); the Sentence tab asks Apple for them.
            const _SentenceTranslationTile(),
            if (GemmaTranslation.supported) const _HighQualityTranslationTile(),
            const LocalOcrDownloadTile(),
          ],
          // On-device scans of books imported from PDFs read long lines with it;
          // on Android only devices that run on-device OCR can use it.
          if (defaultTargetPlatform == TargetPlatform.iOS ||
              (!lowRamMode &&
                  ref.watch(localOcrModelProvider).asData?.value.supported ==
                      true))
            const NdlTextModelDownloadTile(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ── Download tile widgets ──

/// Android's Mozilla translation models for the lookup sheet's Sentence tab.
/// The tab offers the download too; this row is also where they go away.
class _SentenceTranslationTile extends StatefulWidget {
  const _SentenceTranslationTile();

  @override
  State<_SentenceTranslationTile> createState() =>
      _SentenceTranslationTileState();
}

class _SentenceTranslationTileState extends State<_SentenceTranslationTile> {
  String? _target;
  TranslationStatus? _status;
  bool _busy = false;

  /// The last download or remove.
  TileOutcome? _outcome;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final target = translationTargetFor(Localizations.localeOf(context));
    if (target != _target) {
      _target = target;
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final status = await translationStatus(_target!);
    if (mounted) setState(() => _status = status);
  }

  Future<void> _run(TileAction action, Future<void> Function() work) async {
    setState(() {
      _busy = true;
      _outcome = null;
    });
    Object? error;
    try {
      await work();
    } catch (e) {
      logFailure(switch (action) {
        TileAction.download => 'translation.download_failed',
        TileAction.delete => 'translation.delete_failed',
      }, e);
      error = e;
    }
    _outcome = (action: action, error: error);
    if (mounted) setState(() => _busy = false);
    await _refresh();
  }

  Future<void> _download() async {
    if (!await confirmTranslationMemory(context) || !mounted) return;
    final network = await askNetwork(
      context,
      size: translationDownloadSize(_target!),
      body: (size) => context.l10n.translationMobileDataBody(size: size),
    );
    if (network == null || !mounted) return;
    await _run(
      TileAction.download,
      () => downloadTranslation(_target!, network),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    if (status == null || status == TranslationStatus.unsupported) {
      return const SizedBox();
    }
    final l = context.l10n;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: Icon(
            Icons.g_translate_outlined,
            color: theme.colorScheme.primary,
          ),
          title: Text(l.downloadsSentenceTranslationTitle),
          subtitle: Text(
            '${l.downloadsSentenceTranslationSubtitle} '
            '(${translationDownloadSize(_target!)})',
          ),
          trailing: _busy
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : status == TranslationStatus.installed
              ? IconButton(
                  tooltip: l.commonRemove,
                  icon: Icon(
                    Icons.delete_outline,
                    color: theme.colorScheme.error,
                  ),
                  onPressed: () => _run(TileAction.delete, deleteTranslation),
                )
              : FilledButton.tonal(
                  onPressed: _download,
                  child: Text(l.commonDownload),
                ),
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: LinearProgressIndicator(),
          ),
        // The pairs keep their partial files, so a Wi-Fi stop says so.
        if (_outcome case final outcome?)
          DownloadOutcomeText(outcome, kind: DownloadKind.translationModel),
      ],
    );
  }
}

/// Android's optional Gemma model for High quality sentence translation.
/// The download outlives this screen: the provider holds it.
class _HighQualityTranslationTile extends ConsumerStatefulWidget {
  const _HighQualityTranslationTile();

  @override
  ConsumerState<_HighQualityTranslationTile> createState() =>
      _HighQualityTranslationTileState();
}

class _HighQualityTranslationTileState
    extends ConsumerState<_HighQualityTranslationTile> {
  /// The last removal, or a download seen to finish here. The provider
  /// holds a failed download, also one that failed while the tile was gone.
  TileOutcome? _outcome;

  Future<void> _download() async {
    setState(() => _outcome = null);
    // Read before the dialogs: the tile can unmount while one is up.
    final download = ref.read(gemmaDownloadProvider.notifier);
    if (!await confirmHighQualityMemory(context) || !mounted) return;
    await askThenStartHighQuality(context, download);
  }

  Future<void> _remove() async {
    setState(() => _outcome = null);
    Object? error;
    try {
      await ref.read(gemmaDownloadProvider.notifier).remove();
    } catch (e) {
      logFailure('translation.high_quality_delete_failed', e);
      error = e;
    }
    if (mounted) {
      setState(() => _outcome = (action: TileAction.delete, error: error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final state = ref.watch(gemmaDownloadProvider);
    ref.listen(gemmaDownloadProvider, (previous, next) {
      if (next is GemmaDownloading) {
        setState(() => _outcome = null);
      } else if (previous is GemmaDownloading && next is GemmaInstalled) {
        setState(() => _outcome = (action: TileAction.download, error: null));
      }
    });
    final outcome =
        _outcome ??
        switch (state) {
          GemmaDownloadFailed(:final error) => (
            action: TileAction.download,
            error: error,
          ),
          _ => null,
        };
    final removeButton = IconButton(
      tooltip: l.commonRemove,
      icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
      onPressed: _remove,
    );
    final downloadButton = FilledButton.tonal(
      onPressed: _download,
      child: Text(l.commonDownload),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: Icon(
            Icons.auto_awesome_outlined,
            color: theme.colorScheme.primary,
          ),
          title: Text(l.downloadsHighQualityTitle),
          subtitle: Text(switch (state) {
            GemmaDownloading(:final fraction, :final wait) =>
              highQualityDownloadText(
                l,
                percent: (fraction * 100).floor(),
                wait: wait,
              ),
            _ =>
              '${l.downloadsHighQualitySubtitle} '
                  '(${GemmaTranslation.downloadSize()})',
          }),
          trailing: switch (state) {
            GemmaInstalled() => removeButton,
            // A partial download can take up to 2.6 GB.
            GemmaDownloadFailed() || GemmaNotInstalled(hasFiles: true) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [removeButton, downloadButton],
            ),
            GemmaDownloading(:final fraction) when fraction < 1 => IconButton(
              tooltip: l.commonCancel,
              icon: const Icon(Icons.close),
              onPressed: ref.read(gemmaDownloadProvider.notifier).cancel,
            ),
            // At 100% the file is being verified: nothing left to cancel.
            GemmaDownloading() => const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            _ => downloadButton,
          },
        ),
        if (state case GemmaDownloading(:final fraction))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LinearProgressIndicator(
              value: fraction,
              semanticsLabel: l.downloadsHighQualityTitle,
            ),
          ),
        // Its job waits for Wi-Fi rather than stopping, so it has no kind.
        if (outcome != null) DownloadOutcomeText(outcome, kind: null),
      ],
    );
  }
}

// Zip sizes for the mobile-data question, rounded: KANJIDIC English was
// 0.7 MB in October 2026, the JPDB v2.2 zip 6.0 MB, the KanjiVG r20250816
// zip 21.5 MB and the UniDic-lite archive 45 MB.
const _kanjidicSize = '0.7 MB';
const _jpdbSize = '6 MB';
const _kanjiVgSize = '22 MB';
const _enhancedFuriganaSize = '45 MB';
