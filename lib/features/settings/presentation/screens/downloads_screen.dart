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
import 'package:mekuru/features/dictionary/presentation/screens/dictionary_catalog_screen.dart';
import 'package:mekuru/features/dictionary/presentation/widgets/catalog_dictionary_tile.dart';
import 'package:mekuru/features/manga/presentation/providers/local_ocr_providers.dart';
import 'package:mekuru/features/manga/presentation/widgets/local_ocr_widgets.dart';
import 'package:mekuru/features/manga/presentation/widgets/manga_ocr_ios_download_tile.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/features/settings/presentation/providers/jpdb_freq_providers.dart';
import 'package:mekuru/features/settings/presentation/providers/enhanced_furigana_dict_providers.dart';
import 'package:mekuru/features/settings/presentation/providers/kanjidic_providers.dart';
import 'package:mekuru/features/settings/presentation/providers/kanjivg_providers.dart';
import 'package:mekuru/shared/widgets/download_status.dart';
import 'package:mekuru/shared/widgets/mobile_data_dialog.dart';
import 'package:mekuru/features/settings/presentation/widgets/starter_pack_card.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/utils/app_routes.dart';
import 'package:mekuru/shared/utils/haptics.dart';
import 'package:mekuru/shared/widgets/settings/settings_rows.dart';

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
      ref.read(jpdbFreqProvider.notifier).checkStatus();
      ref.read(kanjidicProvider.notifier).checkStatus();
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
    final jpdbFreqState = ref.watch(jpdbFreqProvider);
    final kanjidicState = ref.watch(kanjidicProvider);
    final enhancedFuriganaState = ref.watch(enhancedFuriganaDictProvider);
    final theme = Theme.of(context);

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
          _KanjidicTile(state: kanjidicState, theme: theme),
          if (kanjidicState.isDownloading)
            DictionaryDownloadProgress(progress: kanjidicState.progress),
          if (kanjidicState.error != null)
            DownloadErrorText(text: kanjidicState.error!),
          if (kanjidicState.successMessage != null)
            DownloadSuccessText(text: kanjidicState.successMessage!),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: DownloadAttributionText(
              linkText: 'KANJIDIC',
              url: edrdgKanjidicUrl,
              suffix:
                  ' by the Electronic Dictionary Research and '
                  'Development Group (EDRDG), licensed under CC BY-SA 4.0.',
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
          _KanjiVgTile(state: kanjiVgState, theme: theme),
          if (kanjiVgState.isDownloading)
            DownloadProgress(
              progress: kanjiVgState.progress,
              label: kanjiVgState.progress < 0.9
                  ? l10n.downloadsDownloadingPercent(
                      percent: (kanjiVgState.progress * 100).toInt(),
                    )
                  : l10n.downloadsExtractingFiles,
            ),
          if (kanjiVgState.error != null)
            DownloadErrorText(text: kanjiVgState.error!),
          if (kanjiVgState.successMessage != null)
            DownloadSuccessText(text: kanjiVgState.successMessage!),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: DownloadAttributionText(
              prefix: 'Kanji stroke order data by ',
              linkText: 'KanjiVG',
              url: 'https://kanjivg.tagaini.net/',
              suffix: ' (Ulrich Apel), licensed under CC BY-SA 3.0.',
            ),
          ),
          const SizedBox(height: 8),

          // JPDB Frequency
          _JpdbFreqTile(state: jpdbFreqState, theme: theme),
          if (jpdbFreqState.isDownloading)
            DictionaryDownloadProgress(progress: jpdbFreqState.progress),
          if (jpdbFreqState.error != null)
            DownloadErrorText(text: jpdbFreqState.error!),
          if (jpdbFreqState.successMessage != null)
            DownloadSuccessText(text: jpdbFreqState.successMessage!),
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

          // Enhanced Furigana Dictionary (UniDic-lite, optional download)
          _EnhancedFuriganaDictTile(state: enhancedFuriganaState, theme: theme),
          // Kill-switch: lets the user disable the enhanced dictionary
          // without deleting the ~250 MB download. Useful as a recovery step
          // if word tapping ever stops working on a particular device.
          if (enhancedFuriganaState.isInstalled)
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
          if (enhancedFuriganaState.error != null)
            DownloadErrorText(text: enhancedFuriganaState.error!),
          if (enhancedFuriganaState.successMessage != null)
            DownloadSuccessText(text: enhancedFuriganaState.successMessage!),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: DownloadAttributionText(
              prefix: 'Powered by ',
              linkText: 'UniDic',
              url: 'https://clrd.ninjal.ac.jp/unidic/',
              suffix:
                  ' (NINJAL), distributed under the BSD/GPL/LGPL triple '
                  'license.',
            ),
          ),
          const SizedBox(height: 8),
          // iOS finds text with Apple Vision and needs only the manga-ocr
          // files; Android's pack and its download run in the native service.
          if (defaultTargetPlatform == TargetPlatform.iOS)
            const MangaOcrIosDownloadTile()
          else ...[
            // iOS language packs belong to the system (Settings > Apps >
            // Translate); the Sentence tab asks Apple for them.
            const _SentenceTranslationTile(),
            const _HighQualityTranslationTile(),
            const LocalOcrDownloadTile(),
          ],
          // On-device scans of scanned free books read long lines with it;
          // on Android only devices that run on-device OCR can use it.
          if (defaultTargetPlatform == TargetPlatform.iOS ||
              ref.watch(localOcrModelProvider).asData?.value.supported == true)
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
  Object? _error;

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

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      logFailure('translation.download_failed', e);
      _error = e;
    }
    if (mounted) setState(() => _busy = false);
    await _refresh();
  }

  Future<void> _download() async {
    if (!await confirmTranslationMemory(context) || !mounted) return;
    final size = translationDownloadSize(_target!);
    if (await okToDownload(
      context,
      context.l10n.translationMobileDataBody(size: size),
    )) {
      await _run(() => downloadTranslation(_target!));
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    if (status == null || status == TranslationStatus.unsupported) {
      return const SizedBox();
    }
    final l = context.l10n;
    final theme = Theme.of(context);
    final error = dictionaryDownloadError(l, _error);
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
                  onPressed: () => _run(deleteTranslation),
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
        if (error != null) DownloadErrorText(text: error),
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
  Object? _removeError;

  Future<void> _download() async {
    setState(() => _removeError = null);
    // Read before the dialogs: the tile can unmount while one is up.
    final download = ref.read(gemmaDownloadProvider.notifier);
    final model = ref.read(translationModelProvider.notifier);
    if (!await confirmHighQualityMemory(context) || !mounted) return;
    if (await okToDownload(
      context,
      context.l10n.translationMobileDataBody(
        size: GemmaTranslation.downloadSize(),
      ),
    )) {
      unawaited(download.start());
      // The only reason to fetch it is to use it.
      model.setChoice(TranslationModelChoice.high);
    }
  }

  Future<void> _remove() async {
    setState(() => _removeError = null);
    try {
      await ref.read(gemmaDownloadProvider.notifier).remove();
    } catch (e) {
      logFailure('translation.high_quality_delete_failed', e);
      if (mounted) setState(() => _removeError = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final state = ref.watch(gemmaDownloadProvider);
    final error = dictionaryDownloadError(
      l,
      _removeError ?? (state is GemmaDownloadFailed ? state.error : null),
    );
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
            GemmaDownloading(:final fraction) =>
              l.translationHighQualityDownloading(
                percent: '${(fraction * 100).floor()}',
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
        if (error != null) DownloadErrorText(text: error),
      ],
    );
  }
}

// Zip sizes for the mobile-data question, rounded: KANJIDIC English was
// 0.7 MB in October 2026, the JPDB v2.2 zip 6.0 MB.
const _kanjidicSize = '0.7 MB';
const _jpdbSize = '6 MB';

class _KanjiVgTile extends ConsumerWidget {
  const _KanjiVgTile({required this.state, required this.theme});

  final KanjiVgState state;
  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final subtitle = state.isDownloaded
        ? l10n.downloadsKanjiStrokeOrderDownloaded(count: state.fileCount)
        : l10n.downloadsKanjiStrokeOrderDescription;

    return ListTile(
      leading: Icon(Icons.brush_outlined, color: theme.colorScheme.primary),
      title: Text(l10n.downloadsKanjiStrokeOrderTitle),
      subtitle: Text(subtitle),
      trailing: _buildTrailing(context, ref),
    );
  }

  Widget _buildTrailing(BuildContext context, WidgetRef ref) {
    if (state.isDownloading || state.isDeleting) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (state.isDownloaded) {
      return IconButton(
        icon: Icon(
          Icons.delete_outline,
          color: Theme.of(context).colorScheme.error,
        ),
        tooltip: context.l10n.downloadsDeleteKanjiDataTooltip,
        onPressed: () => _confirmDelete(context),
      );
    }

    return FilledButton.tonal(
      onPressed: () {
        AppHaptics.light();
        ref.read(kanjiVgProvider.notifier).download();
      },
      child: Text(context.l10n.commonDownload),
    );
  }

  void _confirmDelete(BuildContext context) {
    // Resolved before the dialog opens: the tile can unmount while it's up.
    final container = ProviderScope.containerOf(context, listen: false);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.downloadsDeleteKanjiDataTitle),
        content: Text(ctx.l10n.downloadsDeleteKanjiDataBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              container.read(kanjiVgProvider.notifier).delete();
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

class _JpdbFreqTile extends ConsumerWidget {
  const _JpdbFreqTile({required this.state, required this.theme});

  final JpdbFreqState state;
  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final subtitle = state.isImported
        ? l10n.downloadsWordFrequencyDownloaded
        : l10n.downloadsWordFrequencyDescription;

    return ListTile(
      leading: Icon(Icons.bar_chart_outlined, color: theme.colorScheme.primary),
      title: Text(l10n.downloadsStarterPackWordFrequency),
      subtitle: Text(subtitle),
      trailing: _buildTrailing(context, ref),
    );
  }

  Widget _buildTrailing(BuildContext context, WidgetRef ref) {
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
        tooltip: context.l10n.downloadsDeleteFrequencyDataTooltip,
        onPressed: () => _confirmDelete(context),
      );
    }

    return FilledButton.tonal(
      onPressed: () => askThenDownload(
        context,
        _jpdbSize,
        ref.read(jpdbFreqProvider.notifier).download,
      ),
      child: Text(context.l10n.commonDownload),
    );
  }

  void _confirmDelete(BuildContext context) {
    // Resolved before the dialog opens: the tile can unmount while it's up.
    final container = ProviderScope.containerOf(context, listen: false);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.downloadsDeleteFrequencyDataTitle),
        content: Text(ctx.l10n.downloadsDeleteFrequencyDataBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              container.read(jpdbFreqProvider.notifier).delete();
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

class _KanjidicTile extends ConsumerWidget {
  const _KanjidicTile({required this.state, required this.theme});

  final KanjidicState state;
  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final subtitle = state.isImported
        ? l10n.downloadsKanjidicDownloaded
        : l10n.downloadsKanjidicDescription;

    return ListTile(
      leading: Icon(
        Icons.font_download_outlined,
        color: theme.colorScheme.primary,
      ),
      title: Text(l10n.downloadsKanjidicTitle),
      subtitle: Text(subtitle),
      trailing: _buildTrailing(context, ref),
    );
  }

  Widget _buildTrailing(BuildContext context, WidgetRef ref) {
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
        tooltip: context.l10n.downloadsDeleteKanjidicTooltip,
        onPressed: () => _confirmDelete(context),
      );
    }

    return FilledButton.tonal(
      onPressed: () => askThenDownload(
        context,
        _kanjidicSize,
        ref.read(kanjidicProvider.notifier).download,
      ),
      child: Text(context.l10n.commonDownload),
    );
  }

  void _confirmDelete(BuildContext context) {
    // Resolved before the dialog opens: the tile can unmount while it's up.
    final container = ProviderScope.containerOf(context, listen: false);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.downloadsDeleteKanjidicTitle),
        content: Text(ctx.l10n.downloadsDeleteKanjidicBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              container.read(kanjidicProvider.notifier).delete();
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

class _EnhancedFuriganaDictTile extends ConsumerWidget {
  const _EnhancedFuriganaDictTile({required this.state, required this.theme});

  final EnhancedFuriganaDictState state;
  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final subtitle = state.isInstalled
        ? l10n.downloadsEnhancedFuriganaInstalled
        : l10n.downloadsEnhancedFuriganaDescription;

    return ListTile(
      leading: Icon(
        Icons.spellcheck_outlined,
        color: theme.colorScheme.primary,
      ),
      title: Text(l10n.downloadsEnhancedFuriganaTitle),
      subtitle: Text(subtitle),
      trailing: _buildTrailing(context, ref),
    );
  }

  Widget _buildTrailing(BuildContext context, WidgetRef ref) {
    if (state.isDownloading || state.isUninstalling) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (state.isInstalled) {
      return IconButton(
        icon: Icon(
          Icons.delete_outline,
          color: Theme.of(context).colorScheme.error,
        ),
        tooltip: context.l10n.downloadsEnhancedFuriganaRemoveTooltip,
        onPressed: () => _confirmRemove(context),
      );
    }

    return FilledButton.tonal(
      onPressed: () {
        AppHaptics.light();
        _confirmDownload(context);
      },
      child: Text(context.l10n.commonDownload),
    );
  }

  void _confirmDownload(BuildContext context) {
    // Resolved before the dialog opens: the tile can unmount while it's up.
    final container = ProviderScope.containerOf(context, listen: false);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.downloadsEnhancedFuriganaConfirmDownloadTitle),
        content: Text(ctx.l10n.downloadsEnhancedFuriganaConfirmDownloadBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              container.read(enhancedFuriganaDictProvider.notifier).download();
            },
            child: Text(ctx.l10n.commonDownload),
          ),
        ],
      ),
    );
  }

  void _confirmRemove(BuildContext context) {
    // Resolved before the dialog opens: the tile can unmount while it's up.
    final container = ProviderScope.containerOf(context, listen: false);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.downloadsEnhancedFuriganaConfirmRemoveTitle),
        content: Text(ctx.l10n.downloadsEnhancedFuriganaConfirmRemoveBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              container.read(enhancedFuriganaDictProvider.notifier).uninstall();
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
